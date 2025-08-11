import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, tap, catchError, throwError } from 'rxjs';
import { Router } from '@angular/router';

interface LoginResponse {
  token: string;
  user_id?: number;
  username?: string;
  message?: string;
}

interface RegisterResponse {
  message: string;
  user_id?: number;
  otpAuthUrl?: string;
}

// INTERFACES PARA LOGS - REQUISITOS DE LA ACTIVIDAD ✅
interface LogEntry {
  timestamp: string;          // ✅ Time stamp
  service_api: string;        // ✅ Servicio API de llamada  
  endpoint: string;
  method: string;
  user: string;              // ✅ Usuario
  status_code: number;       // ✅ Status Code
  response_time_ms: number;  // ✅ Response time
  client_ip: string;
  user_agent: string;
  request_size: number;
  response_size: number;
}

interface LogStats {
  total_api_calls: number;
  unique_users: number;
  service_statistics: { [key: string]: number };
  status_code_statistics: { [key: string]: number };
  response_time_statistics: { [key: string]: {
    avg_ms: number;
    min_ms: number;
    max_ms: number;
    total_calls: number;
  }};
}

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private apiUrl = 'https://answering-plastic-euro-suited.trycloudflare.com';

  constructor(
    private http: HttpClient,
    private router: Router
  ) {}

  login(username: string, password: string): Observable<LoginResponse> {
    const loginData = { username, password };

    return this.http.post<LoginResponse>(`${this.apiUrl}/auth/login`, loginData)
      .pipe(
        tap(response => {
          this.saveUserData(response);
        }),
        catchError(this.handleError)
      );
  }

  loginWithOtp(username: string, password: string, otp: string): Observable<LoginResponse> {
    const loginData = { username, password, otp };

    return this.http.post<LoginResponse>(`${this.apiUrl}/auth/login`, loginData)
      .pipe(
        tap(response => {
          this.saveUserData(response);
        }),
        catchError(this.handleError)
      );
  }

  register(username: string, password: string): Observable<RegisterResponse> {
    const registerData = { username, password };
    return this.http.post<RegisterResponse>(`${this.apiUrl}/auth/register`, registerData)
      .pipe(
        catchError(this.handleError)
      );
  }

  logout(): void {
    const token = this.getToken();
    
    if (token) {
      this.http.post(`${this.apiUrl}/auth/logout`, { token }).subscribe();
    }

    localStorage.removeItem('token');
    localStorage.removeItem('username');
    localStorage.removeItem('user_id');
    this.router.navigate(['/login']);
  }

  isLoggedIn(): boolean {
    const token = localStorage.getItem('token');
    return !!token;
  }

  getToken(): string | null {
    return localStorage.getItem('token');
  }

  getCurrentUser(): any {
    const username = localStorage.getItem('username');
    const userId = localStorage.getItem('user_id');
    
    if (username) {
      return {
        username,
        user_id: userId ? parseInt(userId) : null
      };
    }
    return null;
  }

  isTokenExpired(): boolean {
    const token = this.getToken();
    if (!token) return true;

    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      const exp = payload.exp * 1000;
      return Date.now() >= exp;
    } catch {
      return true;
    }
  }

  refreshToken(): Observable<LoginResponse> {
    return this.http.post<LoginResponse>(`${this.apiUrl}/auth/refresh`, {})
      .pipe(
        tap(response => {
          if (response.token) {
            localStorage.setItem('token', response.token);
          }
        }),
        catchError(this.handleError)
      );
  }

  validateToken(): Observable<any> {
    const token = this.getToken();
    if (!token) {
      throw new Error('No token found');
    }

    return this.http.post(`${this.apiUrl}/auth/validate_token`, { token })
      .pipe(
        catchError(this.handleError)
      );
  }

  getLogs(limit: number = 100, service?: string, user?: string): Observable<{logs: LogEntry[], total: number}> {
    let params: any = { limit: limit.toString() };
    
    if (service) params.service = service;
    if (user) params.user = user;

    return this.http.get<{logs: LogEntry[], total: number}>(`${this.apiUrl}/logs`, { params })
      .pipe(
        catchError(this.handleError)
      );
  }

  getLogStats(): Observable<LogStats> {
    return this.http.get<LogStats>(`${this.apiUrl}/logs/stats`)
      .pipe(
        catchError(this.handleError)
      );
  }

  checkGatewayHealth(): Observable<any> {
    return this.http.get(`${this.apiUrl}/`)
      .pipe(
        catchError(this.handleError)
      );
  }

  private saveUserData(response: LoginResponse): void {
    if (response.token) {
      localStorage.setItem('token', response.token);
    }

    if (response.username) {
      localStorage.setItem('username', response.username);
    }

    if (response.user_id) {
      localStorage.setItem('user_id', response.user_id.toString());
    }
  }

  private handleError = (error: any) => {
    if (error.status === 401) {
      localStorage.removeItem('token');
      localStorage.removeItem('username');
      localStorage.removeItem('user_id');
    }
    
    return throwError(() => error);
  };

  demonstrateLogs(): void {
    // Método vacío o eliminado, si no quieres que haga nada
  }
}
