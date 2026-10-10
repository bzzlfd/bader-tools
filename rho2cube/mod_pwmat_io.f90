! ------------------------------------------------------------------
! mod_pwmat_io: readers for PWmat structure and real-space grid
! files.
!
! atom.config (text, angstrom):
!    line 1            : natom (first token)
!    line 2            : skipped
!    lines 3-5         : lattice vectors a1, a2, a3 (first 3 tokens)
!    line 6            : skipped
!    lines 7-...       : natom lines  itype fx fy fz mx my mz
!                        itype is the atomic number.
!
! OUT.RHO (little-endian fortran sequential unformatted):
!    record 1          : int32  n1, n2, n3, nnodes
!                        (the record may hold one extra int32; a
!                        short read list skips the record remainder,
!                        so reading 4 values handles both variants)
!    record 2          : 9 float64 lattice vectors, angstrom,
!                        a1x, a1y, a1z, a2x, a2y, a2z, a3x, a3y, a3z
!                        (stored in memory as AL(:,i) = a_i)
!    records 3-...     : nnodes records of float64 grid data; each
!                        record holds at least nr = n1*n2*n3/nnodes
!                        values (may be padded); the first nr values
!                        are the data.  Linear index runs
!                        i1*n2*n3 + i2*n3 + i3, i.e. n3 fastest.
! ------------------------------------------------------------------
module pwmat_io_mod
   use utils_mod
   implicit none
   private
   public :: atom_config_t, rho_meta_t, read_atom_config, open_rho, &
             read_rho_meta, meta_same, rho_read_first, rho_read_add

   ! tolerance for lattice comparison, angstrom
   real(dp), parameter :: al_tol = 1.0e-5_dp

   type :: atom_config_t
      integer :: natom = 0
      real(dp) :: AL(3,3) = 0.0_dp         ! columns = lattice vectors, angstrom
      integer, allocatable :: itype(:)     ! atomic numbers
      real(dp), allocatable :: xfrac(:,:)  ! (natom, 3), fractional
   end type atom_config_t

   type :: rho_meta_t
      integer :: n(3) = 0                  ! grid n1, n2, n3
      integer :: nnodes = 0
      integer :: nr = 0                    ! grid values per node record
      real(dp) :: AL(3,3) = 0.0_dp         ! columns = lattice vectors, angstrom
   end type rho_meta_t

contains

   subroutine open_rho(filename, u)
      character(*), intent(in) :: filename
      integer, intent(out) :: u
      integer :: ios
      character(256) :: iomsg
      open(newunit=u, file=filename, status='old', action='read', &
           form='unformatted', access='sequential', convert='little_endian', &
           iostat=ios, iomsg=iomsg)
      if (ios /= 0) call die('cannot open '//trim(filename)//': '//trim(iomsg))
   end subroutine open_rho

   subroutine read_rho_meta(u, filename, meta)
      integer, intent(in) :: u
      character(*), intent(in) :: filename
      type(rho_meta_t), intent(out) :: meta
      integer :: ios
      read(u, iostat=ios) meta%n(1), meta%n(2), meta%n(3), meta%nnodes
      if (ios /= 0) call die('reading grid header failed: '//trim(filename))
      read(u, iostat=ios) meta%AL
      if (ios /= 0) call die('reading lattice failed: '//trim(filename))
      if (any(meta%n <= 0) .or. meta%nnodes <= 0) &
         call die('unphysical grid in '//trim(filename))
      if (mod(meta%n(1)*meta%n(2)*meta%n(3), meta%nnodes) /= 0) &
         call die('n1*n2*n3 not divisible by nnodes in '//trim(filename))
      meta%nr = meta%n(1)*meta%n(2)*meta%n(3)/meta%nnodes
   end subroutine read_rho_meta

   logical function meta_same(a, b)
      type(rho_meta_t), intent(in) :: a, b
      meta_same = all(a%n == b%n) .and. a%nnodes == b%nnodes &
                  .and. all(abs(a%AL - b%AL) < al_tol)
   end function meta_same

   subroutine read_atom_config(filename, atoms)
      character(*), intent(in) :: filename
      type(atom_config_t), intent(out) :: atoms
      integer :: u, ios, i
      open(newunit=u, file=filename, status='old', action='read', iostat=ios)
      if (ios /= 0) call die('cannot open '//trim(filename))
      read(u, *, iostat=ios) atoms%natom
      if (ios /= 0 .or. atoms%natom <= 0) &
         call die('bad atom-number line in '//trim(filename))
      read(u, *, iostat=ios)                              ! "LATTICE" line
      if (ios /= 0) call die('unexpected end of '//trim(filename))
      do i = 1, 3
         read(u, *, iostat=ios) atoms%AL(:,i)
         if (ios /= 0) call die('bad lattice line in '//trim(filename))
      end do
      read(u, *, iostat=ios)                              ! "POSITION" line
      if (ios /= 0) call die('unexpected end of '//trim(filename))
      allocate(atoms%itype(atoms%natom), atoms%xfrac(atoms%natom,3))
      do i = 1, atoms%natom
         read(u, *, iostat=ios) atoms%itype(i), atoms%xfrac(i,:)
         if (ios /= 0) call die('bad atom line in '//trim(filename))
      end do
      close(u)
   end subroutine read_atom_config

   subroutine rho_read_first(u, filename, meta, weight, acc, rsum)
      ! read the data records straight into the accumulator, then
      ! scale:  acc = weight * rho.
      ! acc must have exactly n1*n2*n3 elements; it is fully
      ! overwritten, so no second grid-sized array is needed.
      ! rsum returns the plain (unweighted) sum of all grid values,
      ! for the file's density integral.
      integer, intent(in) :: u
      character(*), intent(in) :: filename
      type(rho_meta_t), intent(in) :: meta
      real(dp), intent(in) :: weight
      real(dp), intent(out) :: acc(:)
      real(dp), intent(out) :: rsum
      integer :: i, off, ios
      rsum = 0.0_dp
      do i = 1, meta%nnodes
         off = (i-1)*meta%nr
         read(u, iostat=ios) acc(off+1 : off+meta%nr)
         if (ios /= 0) call die('reading data record failed: '//trim(filename))
         rsum = rsum + sum(acc(off+1 : off+meta%nr))
         acc(off+1 : off+meta%nr) = weight * acc(off+1 : off+meta%nr)
      end do
   end subroutine rho_read_first

   subroutine rho_read_add(u, filename, meta, weight, acc, buf, rsum)
      ! acc = acc + weight * rho, reading through a reusable
      ! one-record buffer.  rsum returns the plain (unweighted)
      ! sum of all grid values, for the file's density integral.
      integer, intent(in) :: u
      character(*), intent(in) :: filename
      type(rho_meta_t), intent(in) :: meta
      real(dp), intent(in) :: weight
      real(dp), intent(inout) :: acc(:)
      real(dp), intent(out) :: buf(:)      ! at least meta%nr elements
      real(dp), intent(out) :: rsum
      integer :: i, off, ios
      rsum = 0.0_dp
      do i = 1, meta%nnodes
         off = (i-1)*meta%nr
         read(u, iostat=ios) buf(1 : meta%nr)
         if (ios /= 0) call die('reading data record failed: '//trim(filename))
         rsum = rsum + sum(buf(1 : meta%nr))
         acc(off+1 : off+meta%nr) = acc(off+1 : off+meta%nr) &
                                    + weight * buf(1 : meta%nr)
      end do
   end subroutine rho_read_add

end module pwmat_io_mod
