program test_pwmat_io
   use utils_mod, only: dp
   use pwmat_io_mod, only: atom_config_t, rho_meta_t, lattice_tol, lattice_same, &
                           read_atom_config, meta_same
   implicit none
   type(atom_config_t) :: atoms
   type(rho_meta_t) :: meta_a, meta_b
   integer :: i
   real(dp), parameter :: tol = 1.0e-12_dp
   real(dp), parameter :: lattice_constant = 5.68452685_dp
   real(dp) :: expected_AL(3,3), expected_xfrac(8,3)

   ! ==================================================================
   ! Test 1: atom.config atom count, card order, and whitespace
   ! 1. Read natom (the atom count) first.
   ! 2. Read cards in either order; here POSITION precedes LATTICE.
   ! 3. Allow spaces and blank lines at the start, between cards,
   !    and between data records within each card.
   ! Run from the project root with: make test
   ! ==================================================================
   call read_atom_config('data/pwmat_io/atom-reordered-blanks.config', atoms)
   call assert_true(atoms%natom == 8, 'atom count')
   call assert_true(size(atoms%itype) == 8, 'atomic number array size')
   call assert_true(all(shape(atoms%xfrac) == [8,3]), 'coordinate array shape')
   call assert_true(all(atoms%itype == [11,11,11,11,17,17,17,17]), 'atomic numbers and order')

   expected_AL = 0.0_dp
   do i = 1, 3
      expected_AL(i,i) = lattice_constant
   end do
   call assert_true(all(abs(atoms%AL - expected_AL) < tol), 'lattice vectors')

   ! Explicit expected coordinates in the original atom order.
   expected_xfrac = transpose(reshape([ &
      0.75_dp, 0.25_dp, 0.25_dp, &
      0.25_dp, 0.75_dp, 0.25_dp, &
      0.25_dp, 0.25_dp, 0.75_dp, &
      0.75_dp, 0.75_dp, 0.75_dp, &
      0.25_dp, 0.25_dp, 0.25_dp, &
      0.75_dp, 0.75_dp, 0.25_dp, &
      0.75_dp, 0.25_dp, 0.75_dp, &
      0.25_dp, 0.75_dp, 0.75_dp], [3,8]))
   call assert_true(all(abs(atoms%xfrac - expected_xfrac) < tol), 'fractional coordinates and order')
   print '(a)', 'PASS: read_atom_config with reordered cards and internal blank lines'

   ! ==================================================================
   ! Test 2: lattice differences at the tolerance are accepted, while
   ! larger differences make OUT.RHO metadata incompatible.
   ! ==================================================================
   meta_a%n = [2, 2, 2]
   meta_a%nnodes = 1
   meta_a%AL = expected_AL
   meta_b = meta_a
   meta_b%AL(1,1) = meta_b%AL(1,1) + lattice_tol
   call assert_true(lattice_same(meta_a%AL, meta_b%AL), 'lattice difference at tolerance')
   call assert_true(meta_same(meta_a, meta_b), 'lattice difference at tolerance')
   meta_b%AL(1,1) = expected_AL(1,1) + 1.01_dp*lattice_tol
   call assert_true(.not. lattice_same(meta_a%AL, meta_b%AL), 'lattice difference above tolerance')
   call assert_true(.not. meta_same(meta_a, meta_b), 'lattice difference above tolerance')
   print '(a)', 'PASS: lattice compatibility tolerance'

contains

   subroutine assert_true(condition, message)
      logical, intent(in) :: condition
      character(*), intent(in) :: message
      if (.not. condition) then
         print '(a)', 'FAIL: '//message
         error stop 1
      end if
   end subroutine assert_true

end program test_pwmat_io
