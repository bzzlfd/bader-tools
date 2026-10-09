! ------------------------------------------------------------------
! mod_utils: shared small helpers: stderr diagnostics, safe string
! parsing, physical constant.
! ------------------------------------------------------------------
module utils_mod
   use iso_fortran_env, only: error_unit, output_unit
   implicit none
   private
   public :: dp, bohr_ang, die, warn, parse_real, cross_product, cell_volume

   integer, parameter :: dp = selected_real_kind(15, 307)

   ! 1 bohr radius in angstrom
   real(dp), parameter :: bohr_ang = 0.529177239_dp

contains

   pure function cross_product(a, b) result(c)
      real(dp), intent(in) :: a(3), b(3)
      real(dp) :: c(3)
      c = [a(2)*b(3) - a(3)*b(2), &
           a(3)*b(1) - a(1)*b(3), &
           a(1)*b(2) - a(2)*b(1)]
   end function cross_product

   pure function cell_volume(AL) result(volume)
      ! AL(:,i) is lattice vector a_i; volume has units of AL cubed.
      real(dp), intent(in) :: AL(3,3)
      real(dp) :: volume
      volume = abs(dot_product(AL(:,1), cross_product(AL(:,2), AL(:,3))))
   end function cell_volume

   subroutine die(msg)
      character(*), intent(in) :: msg
      flush(output_unit)      ! keep stdout/stderr in causal order
      write(error_unit, '(a)') 'ERROR: ' // trim(msg)
      ! quiet nonzero exit: neither "STOP 1" text nor an error-stop
      ! backtrace is wanted for ordinary CLI errors
      call exit(1)
   end subroutine die

   subroutine warn(msg)
      character(*), intent(in) :: msg
      write(error_unit, '(a)') 'WARNING: ' // trim(msg)
   end subroutine warn

   ! parse str as a real number; .false. if it is not one.
   ! only plain numeric literals [0-9eEdD+-.] are accepted:
   ! list-directed reads would otherwise also take "-Inf"/"NaN"
   ! (and tolerate trailing garbage like "0.5x"), which would
   ! silently poison the weight sum.
   logical function parse_real(str, val)
      character(*), intent(in) :: str
      real(dp), intent(out) :: val
      integer :: ios, k
      parse_real = .false.
      val = 0.0_dp
      do k = 1, len_trim(str)
         select case (str(k:k))
         case ('0':'9', 'e', 'E', 'd', 'D', '+', '-', '.')
         case default
            return
         end select
      end do
      read(str, *, iostat=ios) val
      parse_real = (ios == 0)
   end function parse_real

end module utils_mod
