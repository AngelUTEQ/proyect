import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { AuthService } from '../../../core/auth/auth.service';

// Importa la librería para generar QR en JS
import * as QRCode from 'qrcode';

@Component({
  selector: 'app-register',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './register.component.html',
  styleUrls: ['./register.component.css']
})
export class RegisterComponent {
  username = '';
  password = '';
  error = '';
  success = '';

  otpAuthUrl = '';  // URL para OTP que viene del backend
  qrCodeDataUrl = ''; // Aquí guardamos la imagen base64 del QR

  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  onSubmit() {
    if (!this.username || !this.password) {
      this.error = 'Por favor completa todos los campos';
      this.success = '';
      return;
    }

    this.authService.register(this.username, this.password).subscribe({
      next: async (response: any) => {
        this.error = '';
        this.success = 'Registro exitoso. Escanea el QR con Google Authenticator.';

        this.otpAuthUrl = response.otpAuthUrl;

        if (this.otpAuthUrl) {
          // Generar imagen QR base64
          try {
            this.qrCodeDataUrl = await QRCode.toDataURL(this.otpAuthUrl);
          } catch (err) {
            console.error('Error generando QR:', err);
            this.error = 'Error generando código QR.';
            this.qrCodeDataUrl = '';
          }
        }
      },
      error: (err) => {
        this.error = 'No se pudo registrar. Intenta con otro usuario.';
        this.success = '';
      }
    });
  }

  goToLogin() {
    this.router.navigate(['/login']);
  }
}
