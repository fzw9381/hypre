cBHEADER**********************************************************************
c Copyright (c) 2007,  Lawrence Livermore National Laboratory, LLC.
c Produced at the Lawrence Livermore National Laboratory.
c Written by the HYPRE team. UCRL-CODE-222953.
c All rights reserved.
c
c This file is part of HYPRE (see http://www.llnl.gov/CASC/hypre/).
c Please see the COPYRIGHT_and_LICENSE file for the copyright notice, 
c disclaimer, contact information and the GNU Lesser General Public License.
c
c HYPRE is free software; you can redistribute it and/or modify it under the
c terms of the GNU General Public License (as published by the Free Software 
c Foundation) version 2.1 dated February 1999.
c
c HYPRE is distributed in the hope that it will be useful, but WITHOUT ANY 
c WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS 
c FOR A PARTICULAR PURPOSE.  See the terms and conditions of the GNU General
c Public License for more details.
c
c You should have received a copy of the GNU Lesser General Public License
c along with this program; if not, write to the Free Software Foundation,
c Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
c
c $Revision$
cEHEADER**********************************************************************

c-----------------------------------------------------------------------
c Test driver for unstructured matrix-vector interface
c-----------------------------------------------------------------------
 
      program test

      implicit none

      include 'mpif.h'

      integer MAXZONS, MAXBLKS, MAXDIM, MAXLEVELS
      integer HYPRE_PARCSR

      parameter (MAXZONS=4194304)
      parameter (MAXBLKS=32)
      parameter (MAXDIM=3)
      parameter (MAXLEVELS=25)
      parameter (HYPRE_PARCSR=5555)

      integer             num_procs, myid

      integer             dim
      integer             nx, ny, nz
      integer             Px, Py, Pz
      double precision    cx, cy, cz

      integer             generate_matrix, generate_vec
      character           matfile(32), vecfile(32)
      character*32        matfile_str, vecfile_str

      integer*8           A, A_storage
      integer*8           x, b

      double precision    values(4)

      integer             p, q, r

      integer             ierr

      integer             i
      integer             first_local_row, last_local_row
      integer             first_local_col, last_local_col
      integer             indices(MAXZONS)

      double precision    vals(MAXZONS)
      double precision    bvals(MAXZONS)
      double precision    xvals(MAXZONS)
      double precision    sum

c-----------------------------------------------------------------------
c     Initialize MPI
c-----------------------------------------------------------------------

      call MPI_INIT(ierr)

      call MPI_COMM_RANK(MPI_COMM_WORLD, myid, ierr)
      call MPI_COMM_SIZE(MPI_COMM_WORLD, num_procs, ierr)

c-----------------------------------------------------------------------
c     Set defaults
c-----------------------------------------------------------------------

      dim = 3

      nx = 10
      ny = 10
      nz = 10

      Px  = num_procs
      Py  = 1
      Pz  = 1

      cx = 1.0
      cy = 1.0
      cz = 1.0

c-----------------------------------------------------------------------
c     Read options
c-----------------------------------------------------------------------
 
c     open( 5, file='parcsr_matrix_vector.in', status='old')
c
c     read( 5, *) dim
c
c     read( 5, *) nx
c     read( 5, *) ny
c     read( 5, *) nz
c
c     read( 5, *) Px
c     read( 5, *) Py
c     read( 5, *) Pz
c
c     read( 5, *) cx
c     read( 5, *) cy
c     read( 5, *) cz
c
c     write(6,*) 'Generate matrix? !0 yes, 0 no (from file)'
      read(5,*) generate_matrix

      if (generate_matrix .eq. 0) then
c       write(6,*) 'What file to use for matrix (<= 32 chars)?'
        read(5,*) matfile_str
        i = 1
  100   if (matfile_str(i:i) .ne. ' ') then
          matfile(i) = matfile_str(i:i)
        else
          goto 200
        endif
        i = i + 1
        goto 100
  200   matfile(i) = char(0)
      endif

c     write(6,*) 'Generate vector? !0 yes, 0 no (from file)'
      read(5,*) generate_vec

      if (generate_vec .eq. 0) then
c       write(6,*)
c    &    'What file to use for vector (<= 32 chars)?'
        read(5,*) vecfile_str
        i = 1
  300   if (vecfile_str(i:i) .ne. ' ') then
          vecfile(i) = vecfile_str(i:i)
        else
          goto 400
        endif
        i = i + 1
        goto 300
  400   vecfile(i) = char(0)
      endif

c     close( 5 )

c-----------------------------------------------------------------------
c     Check a few things
c-----------------------------------------------------------------------

      if ((Px*Py*Pz) .ne. num_procs) then
         print *, 'Error: Invalid number of processors or topology'
         stop
      endif

      if ((dim .lt. 1) .or. (dim .gt. 3)) then
         print *, 'Error: Invalid problem dimension'
         stop
      endif

      if ((nx*ny*nz) .gt. MAXZONS) then
         print *, 'Error: Invalid number of zones'
         stop
      endif

c-----------------------------------------------------------------------
c     Print driver parameters
c-----------------------------------------------------------------------

      if (myid .eq. 0) then
         print *, 'Matrix built with these parameters:'
         print *, '  (nx, ny, nz) = (', nx, ',', ny, ',', nz, ')'
         print *, '  (Px, Py, Pz) = (',  Px, ',',  Py, ',',  Pz, ')'
         print *, '  (cx, cy, cz) = (', cx, ',', cy, ',', cz, ')'
         print *, '  dim          = ', dim
      endif

c-----------------------------------------------------------------------
c     Compute some grid and processor information
c-----------------------------------------------------------------------

      if (dim .eq. 1) then

c        compute p from Px and myid
         p = mod(myid,Px)

      elseif (dim .eq. 2) then

c        compute p,q from Px, Py and myid
         p = mod(myid,Px)
         q = mod(((myid - p)/Px),Py)

      elseif (dim .eq. 3) then

c        compute p,q,r from Px,Py,Pz and myid
         p = mod(myid,Px)
         q = mod((( myid - p)/Px),Py)
         r = (myid - (p + Px*q))/(Px*Py)

      endif

c----------------------------------------------------------------------
c     Set up the matrix
c-----------------------------------------------------------------------

      values(2) = -cx
      values(3) = -cy
      values(4) = -cz

      values(1) = 0.0
      if (nx .gt. 1) values(1) = values(1) + 2d0*cx
      if (ny .gt. 1) values(1) = values(1) + 2d0*cy
      if (nz .gt. 1) values(1) = values(1) + 2d0*cz

c Generate a Dirichlet Laplacian
      if (generate_matrix .gt. 0) then

c        Standard 7-point laplacian in 3D with grid and anisotropy
c        determined as user settings.

         call HYPRE_GenerateLaplacian(MPI_COMM_WORLD, nx, ny, nz,
     &                                Px, Py, Pz, p, q, r, values,
     &                                A_storage, ierr)

         call HYPRE_ParCSRMatrixGetLocalRange(A_storage,
     &             first_local_row, last_local_row,
     &             first_local_col, last_local_col, ierr)

         call HYPRE_IJMatrixCreate(MPI_COMM_WORLD,
     &             first_local_row, last_local_row,
     &             first_local_col, last_local_col, A, ierr)

         call HYPRE_IJMatrixSetObject(A, A_storage, ierr)

         if (ierr .ne. 0) write(6,*) 'Matrix object set failed'

         call HYPRE_IJMatrixSetObjectType(A, HYPRE_PARCSR, ierr)

      else

         call HYPRE_IJMatrixRead(matfile, MPI_COMM_WORLD,
     &                           HYPRE_PARCSR, A, ierr)

         if (ierr .ne. 0) write(6,*) 'Matrix read failed'

         call HYPRE_IJMatrixGetObject(A, A_storage, ierr)

         if (ierr .ne. 0)
     &      write(6,*) 'Matrix object retrieval failed'

         call HYPRE_ParCSRMatrixGetLocalRange(A_storage,
     &             first_local_row, last_local_row,
     &             first_local_col, last_local_col, ierr)

         if (ierr .ne. 0)
     &      write(6,*) 'Matrix local range retrieval failed'

      endif

      matfile(1) = 'm'
      matfile(2) = 'v'
      matfile(3) = '.'
      matfile(4) = 'o'
      matfile(5) = 'u'
      matfile(6) = 't'
      matfile(7) = '.'
      matfile(8) = 'A'
      matfile(9) = char(0)
   
      call HYPRE_IJMatrixPrint(A, matfile, ierr)

      if (ierr .ne. 0) write(6,*) 'Matrix print failed'
  
c-----------------------------------------------------------------------
c     "RHS vector" test
c-----------------------------------------------------------------------
      if (generate_vec .gt. 0) then
        call HYPRE_IJVectorCreate(MPI_COMM_WORLD, first_local_row,
     &                            last_local_row, b, ierr)

        if (ierr .ne. 0) write(6,*) 'RHS vector creation failed'
  
        call HYPRE_IJVectorSetObjectType(b, HYPRE_PARCSR, ierr)

        if (ierr .ne. 0) write(6,*) 'RHS vector object set failed'
  
        call HYPRE_IJVectorInitialize(b, ierr)

        if (ierr .ne. 0) write(6,*) 'RHS vector initialization failed'
  
c Set up a Dirichlet 0 problem
        do i = 1, last_local_row - first_local_row + 1
          indices(i) = first_local_row - 1 + i
          vals(i) = 0.
        enddo
        call HYPRE_IJVectorSetValues(b,
     &    last_local_row - first_local_row + 1, indices, vals, ierr)

        vecfile(1) = 'm'
        vecfile(2) = 'v'
        vecfile(3) = '.'
        vecfile(4) = 'o'
        vecfile(5) = 'u'
        vecfile(6) = 't'
        vecfile(7) = '.'
        vecfile(8) = 'b'
        vecfile(9) = char(0)
   
        call HYPRE_IJVectorPrint(b, vecfile, ierr)

        if (ierr .ne. 0) write(6,*) 'RHS vector print failed'

      else

        call HYPRE_IJVectorRead(vecfile, MPI_COMM_WORLD,
     &                          HYPRE_PARCSR, b, ierr)

        if (ierr .ne. 0) write(6,*) 'RHS vector read failed'

      endif

      do i = 1, last_local_row - first_local_row + 1
        indices(i) = first_local_row - 1 + i
      enddo

      call HYPRE_IJVectorGetValues(b,
     &  last_local_row - first_local_row + 1, indices, bvals, ierr)
  
      if (ierr .ne. 0) write(6,*) 'RHS vector value retrieval failed'
  
c     Set about to modify every other component of b, by adding the
c     negative of the component

      do i = 1, last_local_row - first_local_row + 1, 2
        indices(i) = first_local_row - 1 + i
        vals(i)    = -bvals(i)
      enddo

      call HYPRE_IJVectorAddToValues(b,
     &   1 + (last_local_row - first_local_row)/2, indices, vals, ierr)

      if (ierr .ne. 0) write(6,*) 'RHS vector value addition failed'
  
      do i = 1, last_local_row - first_local_row + 1
        indices(i) = first_local_row - 1 + i
      enddo

      call HYPRE_IJVectorGetValues(b,
     &  last_local_row - first_local_row + 1, indices, bvals, ierr)

      if (ierr .ne. 0) write(6,*) 'RHS vector value retrieval failed'
  
      sum = 0.
      do i = 1, last_local_row - first_local_row + 1, 2
        sum = sum + bvals(i)
      enddo
  
      if (sum .ne. 0.) write(6,*) 'RHS vector value addition error'

c-----------------------------------------------------------------------
c     "Solution vector" test
c-----------------------------------------------------------------------
      call HYPRE_IJVectorCreate(MPI_COMM_WORLD, first_local_col,
     &                          last_local_col, x, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector creation failed'
  
      call HYPRE_IJVectorSetObjectType(x, HYPRE_PARCSR, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector object set failed'
  
      call HYPRE_IJVectorInitialize(x, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector initialization',
     &                            ' failed'
  
      do i = 1, last_local_col - first_local_col + 1
          indices(i) = first_local_col - 1 + i
          vals(i) = 0.
      enddo

      call HYPRE_IJVectorSetValues(x,
     &  last_local_col - first_local_col + 1, indices, vals, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector value set failed'
  
      vecfile(1)  = 'm'
      vecfile(2)  = 'v'
      vecfile(3)  = '.'
      vecfile(4)  = 'o'
      vecfile(5)  = 'u'
      vecfile(6)  = 't'
      vecfile(7)  = '.'
      vecfile(8)  = 'x'
      vecfile(9) = char(0)
   
      call HYPRE_IJVectorPrint(x, vecfile, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector print failed'
  
      indices(1) = last_local_col
      indices(2) = first_local_col
      vals(1) = -99.
      vals(2) = -45.

      call HYPRE_IJVectorAddToValues(x, 2, indices, vals, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector value addition',
     &                            ' failed'
  
      do i = 1, last_local_col - first_local_col + 1
        indices(i) = first_local_col - 1 + i
      enddo

      call HYPRE_IJVectorGetValues(x,
     &  last_local_col - first_local_col + 1, indices, xvals, ierr)

      if (ierr .ne. 0) write(6,*) 'Solution vector value retrieval',
     &                            ' failed'
  
      if (xvals(1) .ne. -45.)
     &   write(6,*) 'Solution vector value addition error,',
     &              ' first_local_col'

      if (xvals(last_local_col - first_local_col + 1) .ne. -99.)
     &   write(6,*) 'Solution vector value addition error,',
     &              ' last_local_col'

c-----------------------------------------------------------------------
c     Finalize things
c-----------------------------------------------------------------------

      call HYPRE_ParCSRMatrixDestroy(A_storage, ierr)
      call HYPRE_IJVectorDestroy(b, ierr)
      call HYPRE_IJVectorDestroy(x, ierr)

c     Finalize MPI

      call MPI_FINALIZE(ierr)

      stop
      end
