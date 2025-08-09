import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const router = inject(Router);
  
  // Obtener token del localStorage
  const token = localStorage.getItem('token');
  
  // Si hay token, agregarlo a los headers
  if (token) {
    req = req.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`
      }
    });
  }
  
  return next(req).pipe(
    catchError(error => {
      // Si hay error 401 o 403, redirigir al login
      if (error.status === 401 || error.status === 403) {
        localStorage.removeItem('token');
        router.navigate(['/login']);
      }
      
      return throwError(() => error);
    })
  );
};