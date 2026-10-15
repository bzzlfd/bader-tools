! ------------------------------------------------------------------
! mod_pwmat_io: readers for PWmat structure and real-space grid
! files.
!
! atom.config (text, angstrom):
!    first data line   : natom (first token; leading blank lines allowed)
!    LATTICE card      : 3 lattice vectors a1, a2, a3 (first 3 tokens)
!    POSITION card     : natom lines  itype fx fy fz mx my mz
!                        itype is the atomic number.
!    Cards are case-insensitive first tokens, in either order;
!    blank lines and unrelated cards may occur between the blocks.
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
   public :: atom_config_t, rho_meta_t, lattice_tol, lattice_same, read_atom_config, &
             parse_atom_config, open_rho, read_rho_meta, meta_same, rho_read_first, rho_read_add

   ! tolerance for lattice comparison, angstrom
   real(dp), parameter :: lattice_tol = 1.0e-5_dp

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
                  .and. lattice_same(a%AL, b%AL)
   end function meta_same

   pure logical function lattice_same(a, b)
      real(dp), intent(in) :: a(3,3), b(3,3)
      lattice_same = all(abs(a - b) <= lattice_tol)
   end function lattice_same

   subroutine read_atom_config(filename, atoms)
      character(*), intent(in) :: filename
      type(atom_config_t), intent(out) :: atoms
      character(:), allocatable :: text
      integer :: u, ios, nbytes
      ! Load the text unchanged; file and in-memory inputs share one parser.
      open(newunit=u, file=filename, status='old', action='read', &
           access='stream', form='unformatted', iostat=ios)
      if (ios /= 0) call die('cannot open '//trim(filename))
      inquire(unit=u, size=nbytes, iostat=ios)
      if (ios /= 0) call die('cannot determine size of '//trim(filename))
      allocate(character(nbytes) :: text)
      if (nbytes > 0) then
         read(u, iostat=ios) text
         if (ios /= 0) call die('cannot read '//trim(filename))
      end if
      close(u)
      call parse_atom_config(text, atoms, filename)
   end subroutine read_atom_config

   subroutine parse_atom_config(text, atoms, source)
      character(*), intent(in) :: text
      type(atom_config_t), intent(out) :: atoms
      character(*), intent(in), optional :: source
      character(:), allocatable :: line, label
      integer :: pos, ios, i
      allocate(character(8) :: label)
      label = '<string>'
      if (present(source)) label = source
      pos = 1
      if (.not. next_atom_line(text, pos, line)) call die('bad atom-number line in '//label)
      read(line, *, iostat=ios) atoms%natom
      if (ios /= 0 .or. atoms%natom <= 0) &
         call die('bad atom-number line in '//label)
      call find_atom_card(text, pos, 'LATTICE', label)
      do i = 1, 3
         if (.not. next_atom_line(text, pos, line)) call die('bad lattice line in '//label)
         read(line, *, iostat=ios) atoms%AL(:,i)
         if (ios /= 0) call die('bad lattice line in '//label)
      end do
      call find_atom_card(text, pos, 'POSITION', label)
      allocate(atoms%itype(atoms%natom), atoms%xfrac(atoms%natom,3))
      do i = 1, atoms%natom
         if (.not. next_atom_line(text, pos, line)) call die('bad atom line in '//label)
         read(line, *, iostat=ios) atoms%itype(i), atoms%xfrac(i,:)
         if (ios /= 0) call die('bad atom line in '//label)
      end do
   end subroutine parse_atom_config

   subroutine find_atom_card(text, pos, card, source)
      ! Search independently from the start, so card order is immaterial.
      character(*), intent(in) :: text, card, source
      integer, intent(out) :: pos
      character(:), allocatable :: line
      character(32) :: keyword
      integer :: ios, i, code
      pos = 1
      do while (next_atom_line(text, pos, line))
         keyword = ''
         read(line, *, iostat=ios) keyword
         if (ios /= 0) cycle
         do i = 1, len_trim(keyword)
            code = iachar(keyword(i:i))
            if (code >= iachar('a') .and. code <= iachar('z')) &
               keyword(i:i) = achar(code - iachar('a') + iachar('A'))
         end do
         if (keyword == card) return
      end do
      call die('missing '//card//' card in '//source)
   end subroutine find_atom_card

   logical function next_atom_line(text, pos, line) result(found)
      ! Return a nonblank line, allowing LF/CRLF and spaces or tabs.
      character(*), intent(in) :: text
      integer, intent(inout) :: pos
      character(:), allocatable, intent(out) :: line
      integer :: length, offset
      found = .false.
      line = ''
      do while (pos <= len(text))
         offset = index(text(pos:), new_line('a'))
         length = len(text) - pos + 1
         if (offset > 0) length = offset - 1
         line = text(pos:pos + length - 1)
         pos = pos + length + 1
         if (len(line) > 0) then
            if (line(len(line):) == achar(13)) line = line(:len(line)-1)
         end if
         if (verify(line, ' '//achar(9)) == 0) cycle
         found = .true.
         return
      end do
   end function next_atom_line

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
