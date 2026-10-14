! ------------------------------------------------------------------
! mod_corecharge: species core charge read from a radial table.
!
! A .corecharge table is a plain text file of '#' or '!' comment
! lines and 'r rho_core' rows: rho_core(r) is the actual all-electron
! core density in e/bohr^3 on a radial mesh, r in bohr, with no 4*pi
! factor included. The table can come from any code that exposes the
! all-electron core charge; tool/run_oncvpsp_from_upf.sh reruns the
! UPF generator input, then tool/extract_oncv_corecharge.sh writes the table.
!
! Core charge is confined to 0 <= r <= rmax, the last tabulated
! radius with |rho_core| above tolerance. Its spherical integral
! 4*pi*int_0^infinity rho_core(r)*r^2 dr gives the core electron count.
!
! The stored density is interpolated and added around atoms of the
! given atomic number, summing contributions from periodic images.
! ------------------------------------------------------------------
module corecharge_mod
   use utils_mod
   use pwmat_io_mod, only: atom_config_t, rho_meta_t
   implicit none
   private
   public :: corecharge_t, read_corecharge, superimpose_corecharge

   real(dp), parameter :: four_pi = 4.0_dp*acos(-1.0_dp)

   ! Density tolerance in e/bohr^3, preserving the previous physical cutoff.
   real(dp), parameter :: rho_core_tol = 1.0e-10_dp/four_pi

   type :: corecharge_t
      integer :: z = 0                     ! atomic number it corrects
      integer :: n = 0                     ! table length
      integer :: imax = 0                  ! last index with |rho_core| > tol
      real(dp), allocatable :: r(:)        ! bohr, strictly increasing
      real(dp), allocatable :: rho_core(:) ! actual input density, e/bohr^3
      real(dp) :: rmax = 0.0_dp            ! r(imax)
      real(dp) :: qcore = 0.0_dp           ! core electrons: 4*pi*int rho_core*r^2 dr
   end type corecharge_t

contains

   subroutine read_corecharge(filename, z, cc)
      ! read a .corecharge table: '#' or '!' comment lines, then
      ! 'r rho_core' rows. Store the density directly; the spherical
      ! integral includes 4*pi, but grid values need no conversion.
      character(*), intent(in) :: filename
      integer, intent(in) :: z
      type(corecharge_t), intent(out) :: cc
      integer :: u, ios, k, capacity
      real(dp) :: radius, density
      character(len=1024) :: line
      real(dp), allocatable :: radii(:), densities(:)

      open(newunit=u, file=filename, status='old', action='read', iostat=ios)
      if (ios /= 0) call die('cannot open '//trim(filename))

      capacity = 4096
      allocate(radii(capacity), densities(capacity))
      cc%z = z
      cc%n = 0
      do
         read(u, '(a)', iostat=ios) line
         if (ios /= 0) exit                       ! eof or error
         line = adjustl(line)
         if (len_trim(line) == 0) cycle
         if (line(1:1) == '#' .or. line(1:1) == '!') then
            ! Old tables from upf2corecharge.sh explicitly label their 4*pi factor.
            if (index(line, 'columns:') > 0 .and. index(line, 'rhoc') > 0 &
                .and. index(line, '4*pi') > 0) &
               call die('old 4*pi-scaled core charge table: '//trim(filename)// &
                        '; regenerate with tool/extract_oncv_corecharge.sh'// &
                        ' or divide column 2 by 4*pi and update the header')
            cycle
         end if
         read(line, *, iostat=ios) radius, density
         if (ios /= 0) call die('bad data line in '//trim(filename)//': '&
                                //trim(line))
         cc%n = cc%n + 1
         if (cc%n > capacity) then
            capacity = capacity*2
            call grow(radii, capacity)
            call grow(densities, capacity)
         end if
         radii(cc%n) = radius
         densities(cc%n) = density
      end do
      close(u)
      if (cc%n < 2) call die('need at least 2 data rows in '//trim(filename))

      allocate(cc%r(cc%n), cc%rho_core(cc%n))
      cc%r = radii(1:cc%n)
      cc%rho_core = densities(1:cc%n)
      if (any(cc%r(2:cc%n) <= cc%r(1:cc%n-1))) &
         call die('radii not strictly increasing in '//trim(filename))

      cc%imax = 0
      do k = cc%n, 1, -1
         if (abs(cc%rho_core(k)) > rho_core_tol) then
            cc%imax = k
            exit
         end if
      end do
      if (cc%imax == 0) &
         call die('core charge is identically zero in '//trim(filename))
      cc%rmax = cc%r(cc%imax)
      if (abs(cc%rho_core(cc%n)) > rho_core_tol) &
         call warn('core charge still nonzero at the last tabulated '&
                   //'radius in '//trim(filename)//' (table truncated?)')

      cc%qcore = 0.0_dp
      do k = 2, cc%n
         cc%qcore = cc%qcore + 0.5_dp*(cc%rho_core(k)*cc%r(k)**2 &
                                       + cc%rho_core(k-1)*cc%r(k-1)**2) &
                              *(cc%r(k) - cc%r(k-1))
      end do
      cc%qcore = four_pi*cc%qcore
   contains
      subroutine grow(a, mnew)
         real(dp), allocatable, intent(inout) :: a(:)
         integer, intent(in) :: mnew
         real(dp), allocatable :: tmp(:)
         call move_alloc(a, tmp)
         allocate(a(mnew))
         a(1:size(tmp)) = tmp
      end subroutine grow
   end subroutine read_corecharge

   subroutine superimpose_corecharge(cc, atoms, meta, acc)
      ! Add rho_core(|r_grid - R_atom|) for each atom with itype == cc%z.
      ! Search an unwrapped grid around the atom, then wrap only the
      ! accumulator indices: distinct periodic images must all contribute.
      type(corecharge_t), intent(in) :: cc
      type(atom_config_t), intent(in) :: atoms
      type(rho_meta_t), intent(in) :: meta
      real(dp), intent(inout) :: acc(:)

      real(dp) :: ALb(3,3)     ! columns are lattice vectors
      real(dp) :: volume, face_area, cell_width(3), dfmax(3)
      real(dp) :: df(3), dv(3), d
      integer :: ia, axis, i, j, k, ii, jj, kk
      integer :: ifrom(3), ito(3), linear_index

      ALb = meta%AL/bohr_ang
      volume = cell_volume(ALb)
      ! Distance between the faces at fractional coordinate 0 and 1:
      ! width_i = V / |a_j x a_k|, valid for nonorthogonal cells too.
      do axis = 1, 3
         j = mod(axis, 3) + 1
         k = mod(axis + 1, 3) + 1
         face_area = norm2(cross_product(ALb(:,j), ALb(:,k)))
         cell_width(axis) = volume/max(face_area, 1.0e-300_dp)
      end do
      dfmax = cc%rmax/cell_width

      do ia = 1, atoms%natom
         if (atoms%itype(ia) /= cc%z) cycle
         do i = 1, 3
            ! a grid index along an axis sits at fractional (index-1)/n
            ifrom(i) = floor(meta%n(i)*(atoms%xfrac(ia,i) - dfmax(i))) + 1
            ito(i) = floor(meta%n(i)*(atoms%xfrac(ia,i) + dfmax(i))) + 1
         end do
         do i = ifrom(1), ito(1)
            ii = modulo(i - 1, meta%n(1)) + 1
            df(1) = real(i - 1, dp)/real(meta%n(1), dp) - atoms%xfrac(ia,1)
            do j = ifrom(2), ito(2)
               jj = modulo(j - 1, meta%n(2)) + 1
               df(2) = real(j - 1, dp)/real(meta%n(2), dp) - atoms%xfrac(ia,2)
               do k = ifrom(3), ito(3)
                  kk = modulo(k - 1, meta%n(3)) + 1
                  df(3) = real(k - 1, dp)/real(meta%n(3), dp) - atoms%xfrac(ia,3)

                  dv = matmul(ALb, df)
                  d = norm2(dv)
                  if (d <= cc%rmax) then
                     linear_index = (ii - 1)*meta%n(2)*meta%n(3) + (jj - 1)*meta%n(3) + kk
                     acc(linear_index) = acc(linear_index) + core_density_at_radius(cc, d)
                  end if
               end do
            end do
         end do
      end do

   end subroutine superimpose_corecharge

   pure function core_density_at_radius(cc, radius) result(density)
      ! Linear interpolation of the stored rho_core; clamp below r(1)
      ! and return zero at and beyond the cutoff rmax.
      type(corecharge_t), intent(in) :: cc
      real(dp), intent(in) :: radius
      real(dp) :: density, fraction
      integer :: lo, hi, mid

      if (radius <= cc%r(1)) then
         density = cc%rho_core(1)
      else if (radius >= cc%rmax) then
         density = 0.0_dp
      else
         lo = 1
         hi = cc%imax
         do while (hi - lo > 1)
            mid = (lo + hi)/2
            if (cc%r(mid) <= radius) then
               lo = mid
            else
               hi = mid
            end if
         end do
         fraction = (radius - cc%r(lo))/(cc%r(hi) - cc%r(lo))
         density = cc%rho_core(lo)*(1.0_dp - fraction) + cc%rho_core(hi)*fraction
      end if
   end function core_density_at_radius

end module corecharge_mod
