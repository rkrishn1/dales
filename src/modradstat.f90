!> \file modradstat.f90
!!  Calculates the radiative statistics


!>
!!  Calculates the radiative statistics
!>
!! Profiles of the radiative statistics. Written to radstat.expnr
!! If netcdf is true, this module also writes in the profiles.expnr.nc output
!!  \author Stephan de Roode, TU Delft
!  This file is part of DALES.
!
! DALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! DALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
!  Copyright 1993-2009 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!
module modradstat

  use modglobal, only : longint

implicit none
!private
PUBLIC :: initradstat, radstat, exitradstat
save
!NetCDF variables
  integer,parameter :: nvar = 12
  character(80),dimension(nvar,4) :: ncname

  real    :: dtav=-1, timeav
  integer(kind=longint) :: itimeav,tnextwrite
  integer,save :: nsamples=0
  logical :: lstat= .false. !< switch to enable the radiative statistics (on/off)
  logical :: lradclearair= .false. !< switch to enable the radiative statistics (on/off)

!   --------------
  real :: rdtmn
  real, allocatable :: thltendav(:)
  real, allocatable :: thllwtendav(:)
  real, allocatable :: thlswtendav(:)
  real, allocatable :: lwuav(:)
  real, allocatable :: lwdav(:)
  real, allocatable :: swdav(:)
  real, allocatable :: swuav(:)
  real, allocatable :: lwucaav(:)
  real, allocatable :: lwdcaav(:)
  real, allocatable :: swdcaav(:)
  real, allocatable :: swucaav(:)

  real, allocatable :: thltendmn(:)
  real, allocatable :: thllwtendmn(:)
  real, allocatable :: thlswtendmn(:)
  real, allocatable :: lwumn(:)
  real, allocatable :: lwdmn(:)
  real, allocatable :: swdmn(:)
  real, allocatable :: swumn(:)
  real, allocatable :: lwucamn(:)
  real, allocatable :: lwdcamn(:)
  real, allocatable :: swdcamn(:)
  real, allocatable :: swucamn(:)
  real, allocatable :: thlradlsmn(:)

contains
!> Initialization routine, reads namelists and inits variables
  subroutine initradstat
    use modmpi,    only : myid,mpierr, comm3d,my_real, mpi_logical
    use modglobal, only : dtmax, k1,kmax, ifnamopt,fname_options, ifoutput,&
                          cexpnr,timeav_glob,ladaptive,dt_lim,btime,tres
    use modstat_nc, only : lnetcdf,define_nc,ncinfo
    use modgenstat, only : itimeav_prof=>itimeav,ncid_prof=>ncid

    implicit none

    integer ierr
    namelist/NAMRADSTAT/ &
    dtav,timeav,lstat,lradclearair

    timeav=timeav_glob
    lstat = .false.

    if(myid==0)then
      open(ifnamopt,file=fname_options,status='old',iostat=ierr)
      read (ifnamopt,NAMRADSTAT,iostat=ierr)
      if (ierr > 0) then
        print *, 'Problem in namoptions NAMRADSTAT'
        print *, 'iostat error: ', ierr
        stop 'ERROR: Problem in namoptions NAMRADSTAT'
      endif
      write(6 ,NAMRADSTAT)
      close(ifnamopt)
    end if

    call MPI_BCAST(dtav  ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(timeav,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(lstat ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(lradclearair,1,MPI_LOGICAL,0,comm3d,mpierr)
    itimeav = timeav/tres

    tnextwrite = itimeav +btime

    if(.not.(lstat)) return
    dt_lim = min(dt_lim,tnextwrite)

    if (.not.ladaptive .and. abs(timeav/dtmax-nint(timeav/dtmax))>1e-4) then
      stop 'MODRADSTAT WARNING: timeav should be an integer multiple of dtmax'
    end if
    if (dtav/=-1 .and. myid==0) then
      write(*,*) 'MODRADSTAT: dtav is not used. The output is an average over all profiles now.'
    end if

    allocate(lwuav(k1))
    allocate(lwdav(k1))
    allocate(swdav(k1))
    allocate(swuav(k1))
    allocate(lwucaav(k1))
    allocate(lwdcaav(k1))
    allocate(swdcaav(k1))
    allocate(swucaav(k1))
    allocate(thllwtendav(k1))
    allocate(thltendav(k1))
    allocate(thlswtendav(k1))

    allocate(lwumn(k1))
    allocate(lwdmn(k1))
    allocate(swdmn(k1))
    allocate(swumn(k1))
    allocate(lwucamn(k1))
    allocate(lwdcamn(k1))
    allocate(swdcamn(k1))
    allocate(swucamn(k1))
    allocate(thllwtendmn(k1))
    allocate(thltendmn(k1))
    allocate(thlswtendmn(k1))
    allocate(thlradlsmn(k1))

    lwumn = 0.0
    lwdmn = 0.0
    swdmn = 0.0
    swumn = 0.0
    lwucamn = 0.0
    lwdcamn = 0.0
    swdcamn = 0.0
    swucamn = 0.0
    thltendmn = 0.0
    thllwtendmn = 0.0
    thlswtendmn = 0.0
    thlradlsmn  = 0.0
    rdtmn = 0.0

    if(myid==0)then
      open (ifoutput,file='radstat.'//cexpnr,status='replace')
      close (ifoutput)
    end if
    if (lnetcdf) then
!      idtav = idtav_prof
      itimeav = itimeav_prof
      tnextwrite = itimeav+btime
!      nsamples = itimeav/idtav

      if (myid==0) then
        call ncinfo(ncname( 1,:),'thltend','Total radiative tendency','K/s','tt')
        call ncinfo(ncname( 2,:),'thllwtend','Long wave radiative tendency','K/s','tt')
        call ncinfo(ncname( 3,:),'thlswtend','Short wave radiative tendency','K/s','tt')
        call ncinfo(ncname( 4,:),'thlradls','Large scale radiative tendency','K/s','tt')
        call ncinfo(ncname( 5,:),'lwu','Long wave upward radiative flux','W/m^2','mt')
        call ncinfo(ncname( 6,:),'lwd','Long wave downward radiative flux','W/m^2','mt')
        call ncinfo(ncname( 7,:),'swu','Short wave upward radiative flux','W/m^2','mt')
        call ncinfo(ncname( 8,:),'swd','Short wave downward radiative flux','W/m^2','mt')
        call ncinfo(ncname( 9,:),'lwuca','Long wave clear air upward radiative flux','W/m^2','mt')
        call ncinfo(ncname(10,:),'lwdca','Long wave clear air downward radiative flux','W/m^2','mt')
        call ncinfo(ncname(11,:),'swuca','Short wave clear air upward radiative flux','W/m^2','mt')
        call ncinfo(ncname(12,:),'swdca','Short wave clear air downward radiative flux','W/m^2','mt')

        call define_nc( ncid_prof, NVar, ncname)
      end if

   end if

  end subroutine initradstat
!> General routine, does the timekeeping
  subroutine radstat
    use modglobal, only : rkStep,rkMaxStep,timee,dt_lim
    implicit none
    if (.not. lstat) return
    if (rkStep/=rkMaxStep) return
    ! JvdD radiation statistics now performed every timestep. For mcICA
    ! radiation, this gives output that is much more consistent with the actual
    ! tendency used in the model.
    call do_radstat
    if(timee<tnextwrite) then
      dt_lim = minval((/dt_lim,tnextwrite-timee/))
      return
    end if
    if (timee>=tnextwrite) then
      tnextwrite = tnextwrite+itimeav
      call writeradstat
    end if
    dt_lim = minval((/dt_lim,tnextwrite-timee/))

  end subroutine radstat

!> Calculates the statistics
  subroutine do_radstat

    use modmpi,     only : slabsum
    use modglobal,  only : kmax,rslabs,cp,dzf,i1,j1,k1,ih,jh,rdt
    use modfields,  only : thlpcar,rhof,exnf
    use modraddata, only : lwd,lwu,swd,swu,thlprad

    implicit none
    integer :: k

    lwdav=0.; lwuav=0.; swdav=0.; swuav=0.
    thltendav=0.; thllwtendav=0.; thlswtendav=0.; thltendav=0.

    call slabsum(lwdav ,1,k1,lwd ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(lwuav ,1,k1,lwu ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(swdav ,1,k1,swd ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(swuav ,1,k1,swu ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(thltendav ,1,k1,thlprad ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    do k=1,kmax
      thllwtendav(k) = -(lwdav(k+1)-lwdav(k)+lwuav(k+1)-lwuav(k))/(rhof(k)*exnf(k)*cp*dzf(k))
      thlswtendav(k) = -(swdav(k+1)-swdav(k)+swuav(k+1)-swuav(k))/(rhof(k)*exnf(k)*cp*dzf(k))
    end do

 !    ADD SLAB AVERAGES TO TIME MEAN

    lwumn = lwumn + lwuav*rdt/rslabs
    lwdmn = lwdmn + lwdav*rdt/rslabs
    swdmn = swdmn + swdav*rdt/rslabs
    swumn = swumn + swuav*rdt/rslabs
    thltendmn = thltendmn + thltendav*rdt/rslabs
    thllwtendmn = thllwtendmn + thllwtendav*rdt/rslabs
    thlswtendmn = thlswtendmn + thlswtendav*rdt/rslabs
    thlradlsmn  = thlradlsmn  + thlpcar*rdt

    rdtmn = rdtmn + rdt

    if (lradclearair) call radclearair
  end subroutine do_radstat

  subroutine radclearair
    use modradfull,    only : d4stream
    use modglobal,    only : imax,i1,ih,jmax,j1,jh,kmax,k1,cp,dzf,rlv,rd,zf,pref0,rslabs,rdt
    use modfields,    only : rhof, exnf,exnh, thl0,qt0,ql0
    use modsurfdata,  only : albedo, tskin, qskin, thvs, qts, ps
    use modmicrodata, only : imicro, imicro_bulk, Nc_0,iqr
    use modraddata,   only : thlprad
    use modmpi,    only :  slabsum
      implicit none
    real, dimension(k1)  :: rhof_b, exnf_b
    real, dimension(2-ih:i1+ih,2-jh:j1+jh,k1) :: temp_b, qv_b, ql_b,swdca,swuca,lwdca,lwuca
    integer :: i,j,k

    real :: exnersurf
    lwdcaav  = 0.
    lwucaav  = 0.
    swdcaav  = 0.
    swucaav  = 0.

    !take care of UCLALES z-shift for thermo variables.
    do k=1,kmax
      rhof_b(k+1)     = rhof(k)
      exnf_b(k+1)     = exnf(k)
      do j=2,j1
        do i=2,i1
          qv_b(i,j,k+1)   = qt0(i,j,k) - ql0(i,j,k)
          ql_b(i,j,k+1)   = 0.
          temp_b(i,j,k+1) = thl0(i,j,k)*exnf(k)+(rlv/cp)*ql0(i,j,k)
        end do
      end do
    end do

    !take care of the surface boundary conditions
    !CvH edit, extrapolation creates instability in surface scheme
    exnersurf = (ps/pref0) ** (rd/cp)
    rhof_b(1) = ps / (rd * thvs * exnersurf)
    exnf_b(1) = exnersurf

    !rhof_b(1) = rhof(1) + 2*zf(1)/dzf(1)*(rhof(1)-rhof(2))
    !exnf_b(1) = exnh(1) + 0.5*dzf(1)*(exnh(1)-exnf(1))

    do j=2,j1
      do i=2,i1
        ql_b(i,j,1)   = 0.! CvH, no ql at surface
        qv_b(i,j,1)   = qskin(i,j) !CvH, no ql at surface thus qv = qt
        temp_b(i,j,1) = tskin(i,j)*exnersurf
      end do
    end do

    call d4stream(i1,ih,j1,jh,k1,tskin,albedo,Nc_0,rhof_b,exnf_b*cp,temp_b,qv_b,ql_b,swdca,swuca,lwdca,lwuca,lclear = .true.)


    call slabsum(lwdcaav ,1,k1,lwdca ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(lwucaav ,1,k1,lwuca ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(swdcaav ,1,k1,swdca ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
    call slabsum(swucaav ,1,k1,swuca ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)

 !    ADD SLAB AVERAGES TO TIME MEAN

    lwucamn = lwucamn + lwucaav*rdt/rslabs
    lwdcamn = lwdcamn + lwdcaav*rdt/rslabs
    swdcamn = swdcamn + swdcaav*rdt/rslabs
    swucamn = swucamn + swucaav*rdt/rslabs
  end subroutine radclearair

!> Write the statistics to file
  subroutine writeradstat
      use modmpi,    only : myid
      use modglobal, only : cexpnr,ifoutput,kmax,k1,zf,zh,rtimee
      use modstat_nc, only: lnetcdf, writestat_nc
      use modgenstat, only: ncid_prof=>ncid,nrec_prof=>nrec

      implicit none
      real,dimension(k1,nvar) :: vars
      integer nsecs, nhrs, nminut,k

      nsecs   = nint(rtimee)
      nhrs    = int(nsecs/3600)
      nminut  = int(nsecs/60)-nhrs*60
      nsecs   = mod(nsecs,60)

      lwumn       = lwumn      /rdtmn   !nsamples
      lwdmn       = lwdmn      /rdtmn   !nsamples
      swdmn       = swdmn      /rdtmn   !nsamples
      swumn       = swumn      /rdtmn   !nsamples
      lwucamn     = lwucamn    /rdtmn   !nsamples
      lwdcamn     = lwdcamn    /rdtmn   !nsamples
      swdcamn     = swdcamn    /rdtmn   !nsamples
      swucamn     = swucamn    /rdtmn   !nsamples
      thllwtendmn = thllwtendmn/rdtmn   !nsamples
      thlswtendmn = thlswtendmn/rdtmn   !nsamples
      thlradlsmn  = thlradlsmn /rdtmn   !nsamples
      thltendmn   = thltendmn  /rdtmn   !nsamples
  !     ----------------------
  !     2.0  write the fields
  !           ----------------

    if(myid==0)then
      open (ifoutput,file='radstat.'//cexpnr,position='append')
      write(ifoutput,'(//A,/A,F5.0,A,I4,A,I2,A,I2,A)') &
      '#--------------------------------------------------------'      &
      ,'#',(timeav),'--- AVERAGING TIMESTEP --- '      &
      ,nhrs,':',nminut,':',nsecs      &
      ,'   HRS:MIN:SEC AFTER INITIALIZATION '
      write (ifoutput,'(A/2A/2A)') &
          '#--------------------------------------------------------------------------' &
          ,'#LEV RAD_FLX_HGHT  THL_HGHT  LW_UP        LW_DN        SW_UP       SW_DN       ' &
          ,'TL_LW_TEND   TL_SW_TEND   TL_LS_TEND   TL_TEND' &
          ,'#    (M)    (M)      (W/M^2)      (W/M^2)      (W/M^2)      (W/M^2)      ' &
          ,'(K/H)         (K/H)        (K/H)        (K/H)'
      do k=1,kmax
        write(ifoutput,'(I4,2F10.2,12E13.4)') &
            k,zh(k), zf(k),&
            lwumn(k),&
            lwdmn(k),&
            swumn(k),&
            swdmn(k),&
            thllwtendmn(k)*3600,&
            thlswtendmn(k)*3600,&
            thlradlsmn(k) *3600,&
            thltendmn(k)  *3600,&
            lwucamn(k),&
            lwdcamn(k),&
            swucamn(k),&
            swdcamn(k)
      end do
      close (ifoutput)
      if (lnetcdf) then
        vars(:, 1) = thltendmn
        vars(:, 2) = thllwtendmn
        vars(:, 3) = thlswtendmn
        vars(:, 4) = thlradlsmn
        vars(:, 5) = lwumn
        vars(:, 6) = lwdmn
        vars(:, 7) = swumn
        vars(:, 8) = swdmn
        vars(:, 9) = lwucamn
        vars(:,10) = lwdcamn
        vars(:,11) = swucamn
        vars(:,12) = swdcamn
       call writestat_nc(ncid_prof,nvar,ncname,vars(1:kmax,:),nrec_prof,kmax)
      end if
    end if ! end if(myid==0)

    rdtmn = 0.0
    lwumn = 0.0
    lwdmn = 0.0
    swdmn = 0.0
    swumn = 0.0
    lwucamn = 0.0
    lwdcamn = 0.0
    swdcamn = 0.0
    swucamn = 0.0
    thllwtendmn = 0.0
    thlswtendmn = 0.0
    thlradlsmn  = 0.0
    thltendmn  = 0.0


  end subroutine writeradstat

!> Cleans up after the run
  subroutine exitradstat
    implicit none

    !deallocate variables that are needed in modradstat

    if(.not.(lstat)) return
    deallocate(lwuav,lwdav,swdav,swuav)
    deallocate(thllwtendav,thlswtendav)
    deallocate(lwumn,lwdmn,swdmn,swumn)
    deallocate(thllwtendmn,thlswtendmn,thlradlsmn)

  end subroutine exitradstat


end module modradstat
