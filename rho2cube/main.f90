! ------------------------------------------------------------------
! convert_rho2cube.x: weighted sum of PWmat OUT.RHO density files,
! written as a Gaussian cube file together with the structure from
! an atom.config file.
!
! usage:
!   convert_rho2cube.x -a atom.config -r OUT.RHO 0.5 -r OUT.RHO2 0.5 -o out.cube
! ------------------------------------------------------------------
program convert_rho2cube
   use iso_fortran_env, only: error_unit, output_unit
   use utils_mod
   use pwmat_io_mod
   use cube_mod
   implicit none

   integer, parameter :: MAXRHO = 64

   character(len=4096) :: atomfile, outfile, arg
   character(len=4096) :: rhofile(MAXRHO)
   character(len=32768) :: comment2, tmps
   real(dp) :: weight(MAXRHO)
   integer :: nrho, nargs, i, u, ios
   real(dp) :: sumw, wval, cellvol_bohr
   logical :: have_a, have_o, exists
   character(len=16) :: ans
   type(atom_config_t) :: atoms
   type(rho_meta_t) :: meta, meta_i
   real(dp), allocatable :: rho(:), buf(:)

   nargs = command_argument_count()
   if (nargs == 0) then
      call print_help()
      stop
   end if

   ! ------------------------- parse arguments -------------------------
   have_a = .false.
   have_o = .false.
   nrho = 0
   i = 1
   do while (i <= nargs)
      call get_command_argument(i, arg)
      select case (trim(arg))
      case ('-h', '--help')
         call print_help()
         stop
      case ('-a')
         if (have_a) call die('option -a given more than once')
         call next_str(i, atomfile)
         have_a = .true.
      case ('-o')
         if (have_o) call die('option -o given more than once')
         call next_str(i, outfile)
         have_o = .true.
      case ('-r')
         nrho = nrho + 1
         if (nrho > MAXRHO) call die('too many -r files')
         call next_str(i, rhofile(nrho))
         weight(nrho) = 1.0_dp
         if (i + 1 <= nargs) then          ! optional weight after the path
            call get_command_argument(i + 1, arg)
            if (parse_real(trim(arg), wval)) then
               weight(nrho) = wval
               i = i + 1
            end if
         end if
      case default
         call die('unknown argument "'//trim(arg)//'", see -h for usage')
      end select
      i = i + 1
   end do

   if (.not. have_a) call die('missing required option -a <atom.config>')
   if (nrho == 0) call die('missing required option -r <OUT.RHO>')
   if (.not. have_o) call die('missing required option -o <output.cube>')

   ! ------------------- refuse to clobber a file ----------------------
   inquire(file = trim(outfile), exist = exists)
   if (exists) then
      write(*, '(a)', advance = 'no') &
         'output file exists: '//trim(outfile)//'   overwrite? [y/N] '
      read(*, '(a)', iostat = ios) ans
      if (ios /= 0 .or. (ans(1:1) /= 'y' .and. ans(1:1) /= 'Y')) then
         write(*, '(a)') 'not overwriting, exit.'
         stop
      end if
   end if

   ! ------------------------- structure -------------------------------
   write(*, '(/,a)') '== atom.config: '//trim(atomfile)//' =='
   call read_atom_config(trim(atomfile), atoms)
   write(*, '(a,i0,a)') '  ', atoms%natom, ' atoms, lattice (angstrom):'
   do i = 1, 3
      write(*, '(3f14.8)') atoms%AL(i,:)
   end do

   ! --------------------- OUT.RHO: weighted mix -----------------------
   ! each file prints its weight, metadata and reading in one block
   sumw = sum(weight(1:nrho))
   if (abs(sumw) < 1.0e-30_dp) call die('the weights sum to zero')
   write(*, '(/,a)') '== OUT.RHO mixture =='
   write(*, '(a,f14.8)') '  weights sum = ', sumw
   if (abs(sumw - 1.0_dp) > 1.0e-12_dp) &
      write(*, '(a,f14.8)') '  normalizing by 1/(weights sum) = ', 1.0_dp/sumw
   flush(output_unit)

   ! first file defines the grid
   write(*, '(a,i0,a,i0,a,f10.6,a,a)') &
      '  [', 1, '/', nrho, ']  weight ', weight(1), '  ', trim(rhofile(1))
   flush(output_unit)
   call open_rho(trim(rhofile(1)), u)
   call read_rho_meta(u, trim(rhofile(1)), meta)
   write(*, '(a,i0,a,i0,a,i0,a,i0,a,i0)') &
      '        grid = ', meta%n(1), ' x ', meta%n(2), ' x ', meta%n(3), &
      '  (', meta%n(1)*meta%n(2)*meta%n(3), ' points), nnodes = ', meta%nnodes
   if (any(abs(meta%AL - atoms%AL) > 1.0e-5_dp)) &
      call warn('lattice in '//trim(rhofile(1))//' differs from '//trim(atomfile))
   allocate(rho(meta%n(1)*meta%n(2)*meta%n(3)))
   call rho_read_first(u, trim(rhofile(1)), meta, weight(1), rho)
   close(u)

   ! remaining files: check meta, accumulate
   if (nrho >= 2) allocate(buf(meta%nr))
   do i = 2, nrho
      write(*, '(a,i0,a,i0,a,f10.6,a,a)') &
         '  [', i, '/', nrho, ']  weight ', weight(i), '  ', trim(rhofile(i))
      flush(output_unit)
      call open_rho(trim(rhofile(i)), u)
      call read_rho_meta(u, trim(rhofile(i)), meta_i)
      if (.not. meta_same(meta, meta_i)) call report_meta_mismatch(i)
      write(*, '(a)') '        metadata consistent with file #1'
      call rho_read_add(u, trim(rhofile(i)), meta, weight(i), rho, buf)
      close(u)
   end do

   ! ----------------- normalize and write the cube --------------------
   if (abs(sumw - 1.0_dp) > 1.0e-12_dp) rho = rho / sumw

   comment2 = 'weighted sum:'
   do i = 1, nrho
      write(tmps, '(a,es10.3,a)') ' ', weight(i), ' * '
      comment2 = trim(comment2)//trim(tmps)//' '//trim(rhofile(i))
      if (i < nrho) comment2 = trim(comment2)//' +'
   end do
   write(tmps, '(a,es10.3,a)') '   (weights sum = ', sumw, ', normalized)'
   comment2 = trim(comment2)//tmps

   write(*, '(/,a)') '== output =='
   call write_cube(trim(outfile), atoms, meta, rho, trim(comment2))

   cellvol_bohr = abs(triple(meta%AL(1,:), meta%AL(2,:), meta%AL(3,:))) / bohr_ang**3
   write(*, '(a)') '  written: '//trim(outfile)
   write(*, '(a,f14.8,a)') &
      '  integral of the mixed density over the cell = ', &
      sum(rho)*cellvol_bohr/real(size(rho), dp), ' e'
   write(*, '(a,f12.8,a,f12.8)') &
      '  density min = ', minval(rho), '   max = ', maxval(rho)

contains

   subroutine next_str(ix, str)
      ! consume the argument after the current option as its value
      integer, intent(inout) :: ix
      character(*), intent(out) :: str
      ix = ix + 1
      if (ix > nargs) call die('option '//trim(arg)//' requires a value')
      call get_command_argument(ix, str)
   end subroutine next_str

   subroutine report_meta_mismatch(k)
      integer, intent(in) :: k
      flush(output_unit)
      write(error_unit, '(a)') 'ERROR: OUT.RHO metadata mismatch:'
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0)') &
         '  file #1    grid = ', meta%n(1), ' x ', meta%n(2), ' x ', meta%n(3), &
         ', nnodes = ', meta%nnodes
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0,a,i0,a,i0)') &
         '  file #', k, '  grid = ', meta_i%n(1), ' x ', meta_i%n(2), ' x ', meta_i%n(3), &
         ', nnodes = ', meta_i%nnodes
      write(error_unit, '(a,es12.4)') '  AL difference (max, angstrom) = ', &
         maxval(abs(meta%AL - meta_i%AL))
      call die('metadata of '//trim(rhofile(k))//' differs from '//trim(rhofile(1)))
   end subroutine report_meta_mismatch

   function triple(a, b, c) result(t)
      real(dp), intent(in) :: a(3), b(3), c(3)
      real(dp) :: t
      t = dot_product(a, cross(b, c))
   end function triple

   function cross(a, b) result(c)
      real(dp), intent(in) :: a(3), b(3)
      real(dp) :: c(3)
      c = [ a(2)*b(3) - a(3)*b(2), a(3)*b(1) - a(1)*b(3), a(1)*b(2) - a(2)*b(1) ]
   end function cross

   subroutine print_help()
      write(*, '(a)') &
         'convert_rho2cube.x -- weighted sum of PWmat OUT.RHO density files,', &
         'written as a Gaussian cube file', &
         '', &
         'usage:', &
         '  convert_rho2cube.x -a ATOMCONFIG -r RHOPATH [WEIGHT] ... -o OUTPUT.cube', &
         '', &
         'options:', &
         '  -a PATH       atom.config file: lattice and atom positions (angstrom)', &
         '  -r PATH [W]   OUT.RHO file with optional weight W (default 1);', &
         '                repeatable. All files must share the same grid.', &
         '                The mixture is normalized by the sum of weights.', &
         '  -o PATH       output cube file (bohr units)', &
         '  -h            print this help', &
         '', &
         'example:', &
         '  convert_rho2cube.x -a atom.config -r OUT.RHO 0.5 -r OUT.RHO2 0.5 -o xxx.cube'
   end subroutine print_help

end program convert_rho2cube
