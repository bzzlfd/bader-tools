program test_cli_output
   use iso_fortran_env, only: int32
   use utils_mod, only: dp
   implicit none

   integer, parameter :: n1 = 2, n2 = 2, n3 = 2
   character(len=4096) :: work_dir, converter
   character(len=4096) :: atom_path, rho_path, core_path
   character(len=4096) :: base_path, corrected_path, implicit_ref_path
   character(len=4096) :: base_log_path, corrected_log_path
   character(len=32768) :: command
   real(dp) :: base_density(n1*n2*n3), corrected_density(n1*n2*n3)
   logical :: exists
   integer :: status

   call get_environment_variable('TEST_WORK_DIR', work_dir, status=status)
   call assert_true(status == 0 .and. len_trim(work_dir) > 0, 'TEST_WORK_DIR is set')
   call get_environment_variable('RHO2CUBE_EXE', converter, status=status)
   call assert_true(status == 0 .and. len_trim(converter) > 0, 'RHO2CUBE_EXE is set')

   atom_path = trim(work_dir)//'/atom.config'
   rho_path = trim(work_dir)//'/OUT.RHO'
   core_path = trim(work_dir)//'/H.corecharge'
   base_path = trim(work_dir)//'/base.cube'
   corrected_path = trim(work_dir)//'/corrected.cube'
   implicit_ref_path = trim(work_dir)//'/corrected.ref.cube'
   base_log_path = trim(work_dir)//'/base.log'
   corrected_log_path = trim(work_dir)//'/corrected.log'

   call delete_if_exists(trim(base_path))
   call delete_if_exists(trim(corrected_path))
   call delete_if_exists(trim(implicit_ref_path))
   call write_atom_config(trim(atom_path))
   call write_rho_file(trim(rho_path))
   call write_core_table(trim(core_path))

   command = quote(trim(converter))//' -a '//quote(trim(atom_path))// &
      ' -r '//quote(trim(rho_path))//' -o '//quote(trim(base_path))// &
      ' > '//quote(trim(base_log_path))//' 2>&1'
   call execute_command_line(trim(command), exitstat=status)
   call assert_true(status == 0, 'converter writes the uncorrected density')

   command = quote(trim(converter))//' -a '//quote(trim(atom_path))// &
      ' -r '//quote(trim(rho_path))//' -o '//quote(trim(corrected_path))// &
      ' --core-rho 1 '//quote(trim(core_path))// &
      ' > '//quote(trim(corrected_log_path))//' 2>&1'
   call execute_command_line(trim(command), exitstat=status)
   call assert_true(status == 0, 'converter writes the core-corrected density')

   inquire(file=trim(corrected_path), exist=exists)
   call assert_true(exists, '-o receives the core-corrected density')
   inquire(file=trim(implicit_ref_path), exist=exists)
   call assert_true(.not. exists, 'no implicit .ref.cube file is created')

   call read_cube_density(trim(base_path), base_density)
   call read_cube_density(trim(corrected_path), corrected_density)
   call assert_true(maxval(corrected_density - base_density) > 0.5_dp, &
      '--core-rho changes the single output density')
   call assert_true(file_contains(trim(base_log_path), &
      'integral of the output density over the cell'), &
      'uncorrected output reports its density integral')
   call assert_true(.not. file_contains(trim(corrected_log_path), &
      'integral of the output density over the cell'), &
      'core-corrected output does not report a misleading grid integral')
   call assert_true(.not. file_contains(trim(corrected_log_path), &
      'core charge added on the grid'), &
      'core-corrected output does not report a grid-sampled core charge')
   call assert_true(file_contains(trim(corrected_log_path), &
      '4*pi*int rho_core*r^2 dr'), &
      'core-corrected output retains the radial core-charge integral')
   call assert_true(file_contains(trim(corrected_log_path), &
      '0.0000     1.000E+00    -1.000E+00'), &
      'a core table shorter than five rows prints its first row safely')

   print '(a)', 'PASS: --core-rho modifies only the explicit -o output'

contains

   function quote(text) result(quoted)
      character(*), intent(in) :: text
      character(len=:), allocatable :: quoted
      quoted = '"'//trim(text)//'"'
   end function quote

   logical function file_contains(path, needle)
      character(*), intent(in) :: path, needle
      character(len=4096) :: line
      integer :: u, ios
      file_contains = .false.
      open(newunit=u, file=path, status='old', action='read')
      do
         read(u, '(a)', iostat=ios) line
         if (ios /= 0) exit
         if (index(line, needle) > 0) then
            file_contains = .true.
            exit
         end if
      end do
      close(u)
   end function file_contains

   subroutine write_atom_config(path)
      character(*), intent(in) :: path
      integer :: u
      open(newunit=u, file=path, status='replace', action='write')
      write(u, '(a)') '1'
      write(u, '(a)') 'LATTICE'
      write(u, '(a)') '2.0 0.0 0.0'
      write(u, '(a)') '0.0 2.0 0.0'
      write(u, '(a)') '0.0 0.0 2.0'
      write(u, '(a)') 'POSITION'
      write(u, '(a)') '1 0.0 0.0 0.0 1 1 1'
      close(u)
   end subroutine write_atom_config

   subroutine write_rho_file(path)
      character(*), intent(in) :: path
      integer :: u, i
      integer(int32) :: dimensions(4)
      real(dp) :: lattice(3,3), density(n1*n2*n3)
      dimensions = [n1, n2, n3, 1]
      lattice = 0.0_dp
      do i = 1, 3
         lattice(i,i) = 2.0_dp
      end do
      density = 0.25_dp
      open(newunit=u, file=path, status='replace', access='sequential', &
           form='unformatted', convert='little_endian')
      write(u) dimensions
      write(u) lattice
      write(u) density
      close(u)
   end subroutine write_rho_file

   subroutine write_core_table(path)
      character(*), intent(in) :: path
      integer :: u
      open(newunit=u, file=path, status='replace', action='write')
      write(u, '(a)') '# r [bohr]  rho_core [e/bohr^3]'
      write(u, '(a)') '0.0 1.0'
      write(u, '(a)') '0.5 0.5'
      write(u, '(a)') '1.0 0.0'
      close(u)
   end subroutine write_core_table

   subroutine read_cube_density(path, density)
      character(*), intent(in) :: path
      real(dp), intent(out) :: density(n1*n2*n3)
      character(len=1024) :: line
      integer :: u, i, j, offset
      open(newunit=u, file=path, status='old', action='read')
      do i = 1, 7
         read(u, '(a)') line
      end do
      do i = 1, n1
         do j = 1, n2
            offset = (i - 1)*n2*n3 + (j - 1)*n3
            read(u, *) density(offset + 1:offset + n3)
         end do
      end do
      close(u)
   end subroutine read_cube_density

   subroutine delete_if_exists(path)
      character(*), intent(in) :: path
      logical :: found
      integer :: u, ios
      inquire(file=path, exist=found)
      if (.not. found) return
      open(newunit=u, file=path, status='old', iostat=ios)
      if (ios == 0) close(u, status='delete')
   end subroutine delete_if_exists

   subroutine assert_true(condition, message)
      logical, intent(in) :: condition
      character(*), intent(in) :: message
      if (.not. condition) then
         print '(a)', 'FAIL: '//message
         error stop 1
      end if
   end subroutine assert_true

end program test_cli_output
