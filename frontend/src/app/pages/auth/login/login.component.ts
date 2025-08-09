import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { AuthService } from '../../../core/auth/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.css']
})
export class LoginComponent implements OnInit {
  username = '';
  password = '';
  otp = '';  // Nuevo campo para OTP
  error = '';
  isLoading = false;
  
  // ==================== INFORMACIÓN DEL SISTEMA DE LOGS ✅ ====================
  showLogInfo = false;
  gatewayStatus = 'Verificando...';
  logStats: any = null;

  // Agrega esta línea para exponer Object en el template:
  public Object = Object;

  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  ngOnInit() {
    // ✅ INICIALIZAR DEMOSTRACIÓN DE LOGS AL CARGAR EL COMPONENTE
    this.initializeLogSystem();
  }

  /**
   * 🧪 INICIALIZAR Y DEMOSTRAR SISTEMA DE LOGS
   */
  initializeLogSystem() {
  
    
    // Verificar estado del API Gateway
    this.authService.checkGatewayHealth().subscribe({
      next: (health) => {
        this.gatewayStatus = `✅ Conectado - ${health.total_logs} logs registrados`;
        
        // Obtener estadísticas para mostrar en UI
        this.authService.getLogStats().subscribe({
          next: (stats) => {
            this.logStats = stats;
         
          }
        });
      },
      error: (err) => {
        this.gatewayStatus = '❌ API Gateway no disponible';
        console.error('Error conectando al gateway:', err);
      }
    });

    // Ejecutar demostración completa
    this.authService.demonstrateLogs();
  }

  onSubmit() {
    if (!this.username || !this.password || !this.otp) {
      this.error = 'Por favor ingresa usuario, contraseña y código OTP';
      return;
    }

    this.isLoading = true;
    this.error = '';

    console.log('🔐 Iniciando login - se registrará en logs con todos los factores requeridos...');

    this.authService.loginWithOtp(this.username, this.password, this.otp).subscribe({
      next: (response) => {
        console.log('✅ Login exitoso registrado en logs:', {
          timestamp: new Date().toISOString(),
          service_api: 'auth',
          endpoint: '/auth/login',
          user: this.username,
          status_code: 200,
          response_time_ms: 'medido automáticamente por middleware'
        });

        const token = localStorage.getItem('token');

        if (token) {
          // Mostrar logs recientes después del login exitoso
          this.showRecentLogs();
          
          // Navegar a tasks después de mostrar logs
          setTimeout(() => {
            this.router.navigate(['/tasks']);
          }, 2000);
        } else {
          this.error = 'Error en la autenticación';
        }
      },
      error: (err) => {
        console.log('❌ Error de login registrado en logs:', {
          timestamp: new Date().toISOString(),
          service_api: 'auth',
          endpoint: '/auth/login',
          user: this.username,
          status_code: err.status || 401,
          error: 'Credenciales incorrectas'
        });

        this.error = 'Usuario, contraseña o OTP incorrectos';
        this.isLoading = false;
      },
      complete: () => {
        this.isLoading = false;
      }
    });
  }

  /**
   * 📊 MOSTRAR LOGS RECIENTES DESPUÉS DEL LOGIN
   */
  showRecentLogs() {
    console.log('📋 Obteniendo logs recientes del sistema...');
    
    this.authService.getLogs(3, 'auth', this.username).subscribe({
      next: (logsResponse) => {
        console.log('📝 LOGS RECIENTES DE ESTE USUARIO:');
        logsResponse.logs.forEach((log, i) => {
          console.log(`   ${i+1}. [${log.timestamp}] ${log.method} ${log.endpoint}`);
          console.log(`      Status: ${log.status_code} | Tiempo: ${log.response_time_ms}ms | Usuario: ${log.user}`);
        });
      }
    });
  }

  goToRegister() {
    this.router.navigate(['/register']);
  }

  /**
   * 🔍 ALTERNAR INFORMACIÓN DE LOGS EN LA UI
   */
  toggleLogInfo() {
    this.showLogInfo = !this.showLogInfo;
    
    if (this.showLogInfo && !this.logStats) {
      this.authService.getLogStats().subscribe({
        next: (stats) => {
          this.logStats = stats;
        }
      });
    }
  }

  /**
   * 🧪 EJECUTAR PRUEBA DE LOGS DESDE LA UI
   */
  testLogSystem() {
    console.log('🧪 Ejecutando prueba manual del sistema de logs...');
    this.authService.demonstrateLogs();
    
    // Actualizar estadísticas
    setTimeout(() => {
      this.authService.getLogStats().subscribe({
        next: (stats) => {
          this.logStats = stats;
        }
      });
    }, 1000);
  }

  // *** MÉTODO NUEVO PARA NAVEGAR AL DASHBOARD ***
  goToDashboard() {
    this.router.navigate(['/dashboard']);
  }
}
