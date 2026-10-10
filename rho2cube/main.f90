! ------------------------------------------------------------------
! convert_rho2cube.x: weighted sum of PWmat OUT.RHO density files,
! written as a Gaussian cube file together with the structure from
! an atom.config file.
!
! usage:
!   convert_rho2cube.x -a atom.config -r OUT.RHO 0.5 -r OUT.RHO2 0.5 -o out.cube
!   convert_rho2cube.x -a atom.config -r OUT.RHO -o out.cube \
!                      -c 11 Na.corecharge 10 -c 17 Cl.corecharge 10
!
! each -c Z FILE [QCORE] adds the all-electron core charge of species Z,
! read from a table file, around every atom of that atomic number
! and writes the valence + core density as an additional reference
! cube (out.ref.cube) for "bader out.cube -ref out.ref.cube".
! ------------------------------------------------------------------
program convert_rho2cube
   use iso_fortran_env, only: error_unit, output_unit
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use utils_mod
   use pwmat_io_mod
   use cube_mod
   use corecharge_mod
   implicit none

   integer, parameter :: MAXRHO = 64
   integer, parameter :: MAXCC = 16
   real(dp), parameter :: qcore_abs_tol = 0.001_dp ! e/atom
   real(dp), parameter :: qcore_rel_tol = 0.001_dp ! 0.1% of expected charge

   character(len=4096) :: atomfile, outfile, arg
   character(len=4096) :: rhofile(MAXRHO)
   character(len=4096) :: ccfile(MAXCC), reffile
   character(len=32768) :: comment2, tmps
   character(len=256) :: charge_message
   real(dp) :: weight(MAXRHO), expected_qcore(MAXCC)
   integer :: nrho, ncc, nargs, i, k, u, ios, zval
   integer :: ccz(MAXCC), nat
   real(dp) :: wval, cellvol_bohr, qsum, qval, qfile, rsum
   logical :: have_a, have_o, exists
   logical :: have_expected_qcore(MAXCC)
   character(len=16) :: ans
   type(atom_config_t) :: atoms
   type(rho_meta_t) :: meta, meta_i
   type(corecharge_t) :: cc(MAXCC)
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
   ncc = 0
   have_expected_qcore = .false.
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
      case ('-c', '--core-charge')
         ncc = ncc + 1
         if (ncc > MAXCC) call die('too many -c/--core-charge options')
         call next_str(i, arg)
         read(arg, *, iostat=ios) zval
         if (ios /= 0 .or. zval <= 0) &
            call die('option -c needs an integer atomic number, got "'&
                     //trim(arg)//'"')
         ccz(ncc) = zval
         call next_str(i, ccfile(ncc))
         if (i + 1 <= nargs) then          ! optional expected charge per atom
            call get_command_argument(i + 1, arg)
            if (parse_real(trim(arg), wval)) then
               if (.not. ieee_is_finite(wval) .or. wval < 0.0_dp) &
                  call die('expected core charge must be finite and nonnegative')
               expected_qcore(ncc) = wval
               have_expected_qcore(ncc) = .true.
               i = i + 1
            end if
         end if
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
   do i = 1, ncc
      do u = i + 1, ncc
         if (ccz(u) == ccz(i)) then
            write(tmps, '(a,i0)') 'option -c/--core-charge given more than once for species ', ccz(i)
            call die(trim(tmps))
         end if
      end do
   end do
   if (ncc > 0) then
      reffile = trim(outfile)
      if (len_trim(reffile) > 5) then
         if (reffile(len_trim(reffile)-4:len_trim(reffile)) == '.cube') &
            reffile = reffile(1:len_trim(reffile)-5)
      end if
      reffile = trim(reffile)//'.ref.cube'
   end if

   ! ------------------- refuse to clobber a file ----------------------
   do i = 1, merge(2, 1, ncc > 0)
      if (i == 1) then
         arg = trim(outfile)
      else
         arg = trim(reffile)
      end if
      inquire(file = trim(arg), exist = exists)
      if (exists) then
         write(*, '(a)', advance = 'no') &
            'output file exists: '//trim(arg)//'   overwrite? [y/N] '
         read(*, '(a)', iostat = ios) ans
         if (ios /= 0 .or. (ans(1:1) /= 'y' .and. ans(1:1) /= 'Y')) then
            write(*, '(a)') 'not overwriting, exit.'
            stop
         end if
      end if
   end do

   ! ------------------------- structure -------------------------------
   write(*, '(/,a)') '== atom.config: '//trim(atomfile)//' =='
   call read_atom_config(trim(atomfile), atoms)
   write(*, '(a,i0,a)') '  ', atoms%natom, ' atoms, lattice (angstrom):'
   do i = 1, 3
      write(*, '(3f14.8)') atoms%AL(:,i)
   end do

   ! --------------------- OUT.RHO: weighted mix -----------------------
   ! each file prints its weight, metadata, reading and integral
   write(*, '(/,a)') '== OUT.RHO mixture =='

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
   cellvol_bohr = cell_volume(meta%AL) / bohr_ang**3
   call rho_read_first(u, trim(rhofile(1)), meta, weight(1), rho, rsum)
   close(u)
   qfile = rsum*cellvol_bohr/real(size(rho), dp)
   write(*, '(a,f14.8)') '        integral over the cell = ', qfile

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
      call rho_read_add(u, trim(rhofile(i)), meta, weight(i), rho, buf, rsum)
      close(u)
      qfile = rsum*cellvol_bohr/real(size(rho), dp)
      write(*, '(a,f14.8)') '        integral over the cell = ', qfile
   end do

   ! ----------------------- write the cube ----------------------------
   comment2 = 'weighted sum:'
   do i = 1, nrho
      write(tmps, '(a,es10.3,a)') ' ', weight(i), ' * '
      comment2 = trim(comment2)//trim(tmps)//' '//trim(rhofile(i))
      if (i < nrho) comment2 = trim(comment2)//' +'
   end do

   ! --------------------- core charge tables --------------------------
   if (ncc > 0) then
      write(*, '(/,a)') '== core charge correction (-c/--core-charge) =='
      do i = 1, ncc
         call read_corecharge(trim(ccfile(i)), ccz(i), cc(i))
         nat = count(atoms%itype == ccz(i))
         if (nat == 0) then
            write(tmps, '(a,i0)') 'no atom with Z = ', ccz(i)
            call die(trim(tmps)//' in '//trim(atomfile))
         end if
         write(*, '(a,i0,a)') '  Z = ', ccz(i), ' from '//trim(ccfile(i))
         write(*, '(a,i0,a,i0,a,f8.3,a,f6.3,a)') &
            '        ', nat, ' atoms;  table ', cc(i)%n, &
            ' pts, rmax = ', cc(i)%rmax, ' bohr (', &
            cc(i)%rmax*bohr_ang, ' angstrom)'
         write(*, '(a,f10.6,a)') '        4*pi*int rho_core*r^2 dr = ', cc(i)%qcore, &
            ' e/atom  (expected Z_core = Z - z_valence)'
         if (have_expected_qcore(i)) then
            write(*, '(a,f10.6,a)') '        expected core charge = ', expected_qcore(i), ' e/atom'
            if (abs(cc(i)%qcore - expected_qcore(i)) > max(qcore_abs_tol, qcore_rel_tol*expected_qcore(i))) then
               write(charge_message, '(a,f12.6,a,f12.6,a)') &
                  'core charge integral = ', cc(i)%qcore, ', expected = ', expected_qcore(i), &
                  ' e/atom; difference exceeds max(0.001 e/atom, 0.1% of expected)'
               flush(output_unit)  ! report the values before the warning on stderr
               call warn(trim(ccfile(i))//': '//trim(charge_message))
            end if
         end if
         write(*, '(a)') '        tail:  r [bohr]    rho_core [e/bohr^3]'&
                        //'    drho_core/dr [e/bohr^4]'
         do k = max(2, cc(i)%n - 2), cc(i)%n
            write(*, '(14x,f10.4,2es14.3)') cc(i)%r(k), cc(i)%rho_core(k), &
               (cc(i)%rho_core(k) - cc(i)%rho_core(k-1))/(cc(i)%r(k) - cc(i)%r(k-1))
         end do
      end do
   end if

   write(*, '(/,a)') '== output =='
   call write_cube(trim(outfile), atoms, meta, rho, trim(comment2))

   qval = sum(rho)*cellvol_bohr/real(size(rho), dp)
   write(*, '(a)') '  written: '//trim(outfile)
   write(*, '(a,f14.8,a)') &
      '  integral of the mixed density over the cell = ', qval, ' e'
   write(*, '(a,f12.8,a,f12.8)') &
      '  density min = ', minval(rho), '   max = ', maxval(rho)

   ! ------------- reference cube: valence + core charge ---------------
   if (ncc > 0) then
      do i = 1, ncc
         call superimpose_corecharge(cc(i), atoms, meta, rho)
      end do
      comment2 = 'valence + core charge: '
      do i = 1, ncc
         write(tmps, '(a,i0,a,i0,a)') &
            'Z=', ccz(i), ' (', count(atoms%itype == ccz(i)), ' atoms) from '
         comment2 = trim(comment2)//trim(tmps)//trim(ccfile(i))
         if (i < ncc) comment2 = trim(comment2)//'; '
      end do
      call write_cube(trim(reffile), atoms, meta, rho, trim(comment2))
      qsum = sum(rho)*cellvol_bohr/real(size(rho), dp)
      write(*, '(a)') '  written: '//trim(reffile)
      write(*, '(a,f14.8,a)') &
         '  integral of valence + core density   = ', qsum, ' e'
      write(*, '(a,f14.8,a)') &
         '  core charge added on the grid        = ', qsum - qval, ' e'
      write(*, '(a,f12.8,a,f12.8)') &
         '  reference density min = ', minval(rho), '   max = ', maxval(rho)
   end if

contains

   subroutine next_str(ix, str)
      ! consume the argument after the current option as its value
      integer, intent(inout) :: ix
      character(*), intent(out) :: str
      ix = ix + 1
      if (ix > nargs) call die('option '//trim(arg)//' requires a value')
      call get_command_argument(ix, str)
   end subroutine next_str

   subroutine report_meta_mismatch(ifile)
      integer, intent(in) :: ifile
      flush(output_unit)
      write(error_unit, '(a)') 'ERROR: OUT.RHO metadata mismatch:'
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0)') &
         '  file #1    grid = ', meta%n(1), ' x ', meta%n(2), ' x ', meta%n(3), &
         ', nnodes = ', meta%nnodes
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0,a,i0,a,i0)') &
         '  file #', ifile, '  grid = ', meta_i%n(1), ' x ', meta_i%n(2), ' x ', meta_i%n(3), &
         ', nnodes = ', meta_i%nnodes
      write(error_unit, '(a,es12.4)') '  AL difference (max, angstrom) = ', &
         maxval(abs(meta%AL - meta_i%AL))
      call die('metadata of '//trim(rhofile(ifile))//' differs from '//trim(rhofile(1)))
   end subroutine report_meta_mismatch

   subroutine print_help()
      write(*, '(a)') &
         'convert_rho2cube.x -- weighted sum of PWmat OUT.RHO density files,', &
         'written as a Gaussian cube file', &
         '', &
         'usage:', &
         '  convert_rho2cube.x -a ATOMCONFIG -r RHOPATH [WEIGHT] ... -o OUTPUT.cube', &
         '                     [-c Z CORECHARGE [QCORE] ...]', &
         '', &
         'options:', &
         '  -a PATH       atom.config file: lattice and atom positions (angstrom)', &
         '  -r PATH [W]   OUT.RHO file with optional weight W (default 1);', &
         '                repeatable. All files must share the same grid.', &
         '                The output is the direct weighted sum W1*rho1 +', &
         '                W2*rho2 + ...; no normalization by the weight sum', &
         '                (negative weights give density differences).', &
         '  -o PATH       output cube file (bohr units)', &
         '  -c, --core-charge Z PATH [QCORE]', &
         '                core charge correction for species with atomic', &
         '                number Z: PATH is a .corecharge table (see', &
         '                tools/upf2corecharge.sh; two columns r [bohr] and', &
         '                rho_core [e/bohr^3], without a 4*pi factor).', &
         '                The interpolated rho_core is', &
         '                added around every Z atom and the valence + core', &
         '                density is written as an extra OUTPUT.ref.cube for', &
         '                "bader OUTPUT.cube -ref OUTPUT.ref.cube". Repeatable.', &
         '                QCORE optionally specifies the expected core charge', &
         '                per atom (>= 0). Warn if the table integral differs', &
         '                by more than max(0.001 e/atom, 0.1% of QCORE).', &
         '  -h            print this help', &
         '', &
         'example:', &
         '  convert_rho2cube.x -a atom.config -r OUT.RHO 0.5 -r OUT.RHO2 0.5 -o xxx.cube', &
         '  convert_rho2cube.x -a atom.config -r OUT.RHO -o NaCl.cube &' &
         //' -c 11 Na.corecharge 10 -c 17 Cl.corecharge 10'
   end subroutine print_help

end program convert_rho2cube
