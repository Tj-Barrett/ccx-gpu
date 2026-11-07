!
!     Linear viscoelastic material: generalized Maxwell model (Prony series),
!     isotropic, small strain, constant Poisson's ratio.
!
!     ABAQUS-style UMAT for CalculiX (compiled in place of ccx's umat.f; the
!     material name must start with ABAQUS, e.g. *MATERIAL, NAME=ABAQUS_VISCO).
!
!     Relaxation modulus (Abaqus convention, relative moduli g_i):
!
!        E(t) = E0 * ( 1 - sum_i g_i * (1 - exp(-t/tau_i)) )
!
!     The whole elasticity tensor relaxes with E(t) (constant nu), so a uniaxial
!     relaxation test follows sigma(t) = E(t)*eps0 exactly.
!
!     Stress = C_inf : eps + sum_i h_i, with C_inf = (1 - sum g_i) C0. Each branch
!     stress h_i is integrated exactly for strain varying linearly within the
!     increment (exponential integrator):
!
!        a_i = exp(-dt/tau_i),  b_i = tau_i/dt * (1 - a_i)    (b_i = 1 for dt = 0)
!        h_i(n+1) = a_i * h_i(n) + g_i * b_i * C0 : d_eps
!
!     The tangent C_inf + sum g_i b_i C0 is exact and constant within an increment.
!
!     *USER MATERIAL, CONSTANTS = 3 + 2*N
!        E0, nu, N, g_1, tau_1, ..., g_N, tau_N
!     *DEPVAR
!        6*N            (branch stresses h_i, Abaqus component order)
!
!     Strains arrive in Abaqus convention (11,22,33,12,13,23, engineering shear).
!
      subroutine umat(stress,statev,ddsdde,sse,spd,scd,
     &  rpl,ddsddt,drplde,drpldt,
     &  stran,dstran,time,dtime,temp,dtemp,predef,dpred,cmname,
     &  ndi,nshr,ntens,nstatv,props,nprops,coords,drot,pnewdt,
     &  celent,dfgrd0,dfgrd1,noel,npt,layer,kspt,kstep,kinc)
!
      implicit none
!
      character*80 cmname
!
      integer ndi,nshr,ntens,nstatv,nprops,noel,npt,layer,kspt,
     &  kstep,kinc
!
      real*8 stress(ntens),statev(nstatv),
     &  ddsdde(ntens,ntens),ddsddt(ntens),drplde(ntens),
     &  stran(ntens),dstran(ntens),time(2),celent,
     &  props(nprops),coords(3),drot(3,3),dfgrd0(3,3),dfgrd1(3,3),
     &  sse,spd,scd,rpl,drpldt,dtime,temp,dtemp,predef,dpred,
     &  pnewdt
!
      integer i,j,k,nterm
      real*8 e0,un,al,um,c0(6,6),eps(6),deps(6),gsum,g,tau,a,b,
     &  ginf,dh(6)
!
      e0=props(1)
      un=props(2)
      nterm=nint(props(3))
      if(nprops.lt.3+2*nterm) then
         write(*,*) '*ERROR in umat_prony_visco: need 3+2*N constants'
         call exit(201)
      endif
      if(nstatv.lt.6*nterm) then
         write(*,*) '*ERROR in umat_prony_visco: need *DEPVAR >= 6*N'
         call exit(201)
      endif
!
!     instantaneous isotropic stiffness C0 (engineering shear)
!
      al=un*e0/((1.d0+un)*(1.d0-2.d0*un))
      um=e0/(2.d0*(1.d0+un))
      do i=1,6
         do j=1,6
            c0(i,j)=0.d0
         enddo
      enddo
      do i=1,3
         do j=1,3
            c0(i,j)=al
         enddo
         c0(i,i)=al+2.d0*um
         c0(i+3,i+3)=um
      enddo
!
      do i=1,6
         eps(i)=stran(i)+dstran(i)
         deps(i)=dstran(i)
      enddo
!
!     long-term part
!
      gsum=0.d0
      do k=1,nterm
         gsum=gsum+props(2+2*k)
      enddo
      ginf=1.d0-gsum
!
      do i=1,6
         stress(i)=0.d0
         do j=1,6
            stress(i)=stress(i)+ginf*c0(i,j)*eps(j)
            ddsdde(i,j)=ginf*c0(i,j)
         enddo
      enddo
!
!     Maxwell branches
!
      do k=1,nterm
         g=props(2+2*k)
         tau=props(3+2*k)
         if(dtime.gt.0.d0) then
            a=dexp(-dtime/tau)
            b=tau/dtime*(1.d0-a)
         else
            a=1.d0
            b=1.d0
         endif
         do i=1,6
            dh(i)=0.d0
            do j=1,6
               dh(i)=dh(i)+g*b*c0(i,j)*deps(j)
               ddsdde(i,j)=ddsdde(i,j)+g*b*c0(i,j)
            enddo
            statev(6*(k-1)+i)=a*statev(6*(k-1)+i)+dh(i)
            stress(i)=stress(i)+statev(6*(k-1)+i)
         enddo
      enddo
!
      return
      end
