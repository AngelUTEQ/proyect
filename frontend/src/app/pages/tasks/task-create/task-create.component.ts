import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';

interface Task {
  name_task: string;
  desc_task: string;
  deadline: string;
  status: number;
  isActive: boolean;
}

interface Status {
  id: number;
  name: string;
}

interface ApiResponse {
  message: string;
  task_id?: number;
}

interface ErrorResponse {
  error: string;
}

@Component({
  selector: 'app-task-create',
  standalone: true,
  imports: [FormsModule, CommonModule],
  templateUrl: './task-create.component.html',
  styleUrls: ['./task-create.component.css']
})
export class TaskCreateComponent implements OnInit {
  private readonly API_GATEWAY_URL = 'http://127.0.0.1:5000';
  
  task: Task = {
    name_task: '',
    desc_task: '',
    deadline: '',
    status: 0,
    isActive: true
  };

  statusList: Status[] = [];
  isLoading: boolean = false;
  isSubmitting: boolean = false;
  errorMessage: string | null = null;
  showSuccess: boolean = false;
  minDate: string = '';

  constructor(
    private http: HttpClient,
    private router: Router
  ) {
    // Establecer fecha mínima como hoy
    const today = new Date();
    this.minDate = today.toISOString().split('T')[0];
  }

  ngOnInit(): void {
    this.loadStatus();
  }

  private getAuthHeaders(): HttpHeaders {
    // CORRECCIÓN: Cambiar 'authToken' por 'token' para que coincida con AuthService
    const token = localStorage.getItem('token');
    
    if (!token) {
      console.error('No se encontró token en localStorage');
      this.router.navigate(['/login']);
      return new HttpHeaders();
    }

    console.log('Token encontrado:', token.substring(0, 20) + '...'); // Debug (solo primeros 20 caracteres)
    
    return new HttpHeaders({
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    });
  }

  private loadStatus(): void {
    this.isLoading = true;
    this.errorMessage = null;

    // Opción 1: Usar datos estáticos (recomendado para solución inmediata)
    this.statusList = [
      { id: 1, name: 'Pendiente' },
      { id: 2, name: 'En Progreso' },
      { id: 3, name: 'Completado' },
    ];
    this.isLoading = false;

    // Opción 2: Intentar obtener desde el servidor con fallback
    /*
    this.http.get<{status: Status[]}>(`${this.API_GATEWAY_URL}/tasks/statuses`, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (response) => {
        this.statusList = response.status;
        this.isLoading = false;
      },
      error: (error) => {
        console.error('Error loading status:', error);
        // Fallback a datos estáticos
        this.statusList = [
          { id: 1, name: 'Pendiente' },
          { id: 2, name: 'En Progreso' },
          { id: 3, name: 'Completado' },
          { id: 4, name: 'Cancelado' }
        ];
        this.isLoading = false;
      }
    });
    */

    // Opción 3: Obtener desde el endpoint de tasks existente
    /*
    this.http.get<any>(`${this.API_GATEWAY_URL}/tasks`, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (response) => {
        // Si la respuesta incluye información de status, usarla
        if (response.statuses) {
          this.statusList = response.statuses;
        } else {
          // Fallback a datos estáticos
          this.statusList = [
            { id: 1, name: 'Pendiente' },
            { id: 2, name: 'En Progreso' },
            { id: 3, name: 'Completado' },
            { id: 4, name: 'Cancelado' }
          ];
        }
        this.isLoading = false;
      },
      error: (error) => {
        console.error('Error loading status:', error);
        // Fallback a datos estáticos
        this.statusList = [
          { id: 1, name: 'Pendiente' },
          { id: 2, name: 'En Progreso' },
          { id: 3, name: 'Completado' },
          { id: 4, name: 'Cancelado' }
        ];
        this.isLoading = false;
      }
    });
    */
  }

  onSubmit(): void {
    if (this.isSubmitting) return;

    this.isSubmitting = true;
    this.errorMessage = null;

    // Validar formulario
    if (!this.validateForm()) {
      this.isSubmitting = false;
      return;
    }

    // Verificar que tenemos el token antes de enviar
    const token = localStorage.getItem('token');
    if (!token) {
      this.handleError('No se encontró token de autenticación. Por favor, inicia sesión nuevamente.');
      this.isSubmitting = false;
      this.router.navigate(['/login']);
      return;
    }

    // Preparar datos para envío
    const taskData = {
      name_task: this.task.name_task.trim(),
      desc_task: this.task.desc_task.trim(),
      deadline: this.task.deadline,
      status: this.task.status,
      isActive: this.task.isActive
    };

    console.log('Enviando datos:', taskData);

    this.http.post<ApiResponse>(`${this.API_GATEWAY_URL}/tasks`, taskData, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (response) => {
        console.log('Task created successfully:', response);
        this.showSuccessMessage();
        this.resetForm();
        this.isSubmitting = false;
        
        // Opcional: navegar a otra página después de crear
        setTimeout(() => {
          this.router.navigate(['/tasks']);
        }, 2000);
      },
      error: (error) => {
        console.error('Error creating task:', error);
        this.handleError(this.getErrorMessage(error));
        this.isSubmitting = false;
      }
    });
  }

  private validateForm(): boolean {
    if (!this.task.name_task.trim()) {
      this.errorMessage = 'El nombre de la tarea es requerido';
      return false;
    }

    if (this.task.name_task.trim().length < 3) {
      this.errorMessage = 'El nombre de la tarea debe tener al menos 3 caracteres';
      return false;
    }

    if (!this.task.desc_task.trim()) {
      this.errorMessage = 'La descripción es requerida';
      return false;
    }

    if (this.task.desc_task.trim().length < 10) {
      this.errorMessage = 'La descripción debe tener al menos 10 caracteres';
      return false;
    }

    if (!this.task.deadline) {
      this.errorMessage = 'La fecha límite es requerida';
      return false;
    }

    if (!this.task.status || this.task.status === 0) {
      this.errorMessage = 'El estado es requerido';
      return false;
    }

    // Validar que la fecha no sea en el pasado
    const selectedDate = new Date(this.task.deadline);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    if (selectedDate < today) {
      this.errorMessage = 'La fecha límite no puede ser en el pasado';
      return false;
    }

    return true;
  }

  private showSuccessMessage(): void {
    this.showSuccess = true;
    setTimeout(() => {
      this.showSuccess = false;
    }, 3000);
  }

  private handleError(message: string): void {
    this.errorMessage = message;
    setTimeout(() => {
      this.errorMessage = null;
    }, 5000);
  }

  private getErrorMessage(error: any): string {
    if (error.error?.error) {
      return error.error.error;
    }
    
    if (error.status === 401) {
      // Redirigir al login en caso de error 401
      setTimeout(() => {
        this.router.navigate(['/login']);
      }, 2000);
      return 'No autorizado. Por favor, inicia sesión nuevamente.';
    }
    
    if (error.status === 403) {
      // Redirigir al login en caso de error 403
      setTimeout(() => {
        this.router.navigate(['/login']);
      }, 2000);
      return 'Token inválido o expirado. Por favor, inicia sesión nuevamente.';
    }
    
    if (error.status === 400) {
      return 'Datos inválidos. Por favor, revisa la información ingresada.';
    }
    
    if (error.status === 500) {
      return 'Error interno del servidor. Por favor, intenta más tarde.';
    }
    
    if (error.status === 502) {
      return 'Error de comunicación con el servidor. Por favor, intenta más tarde.';
    }
    
    if (error.status === 0) {
      return 'No se pudo conectar con el servidor. Verifica que el API Gateway esté funcionando.';
    }
    
    return 'Error inesperado. Por favor, intenta nuevamente.';
  }

  private resetForm(): void {
    this.task = {
      name_task: '',
      desc_task: '',
      deadline: '',
      status: 0,
      isActive: true
    };
  }

  onCancel(): void {
    if (this.hasUnsavedChanges()) {
      const confirmLeave = confirm('¿Estás seguro de que quieres cancelar? Se perderán los cambios no guardados.');
      if (!confirmLeave) return;
    }
    
    this.router.navigate(['/tasks']);
  }

  private hasUnsavedChanges(): boolean {
    return !!(
      this.task.name_task.trim() ||
      this.task.desc_task.trim() ||
      this.task.deadline ||
      this.task.status
    );
  }

  // Método para manejar cambios en el formulario
  onFieldChange(): void {
    if (this.errorMessage) {
      this.errorMessage = null;
    }
  }

  // Método para obtener el nombre del estado seleccionado
  getSelectedStatusName(): string {
    const status = this.statusList.find(s => s.id === this.task.status);
    return status ? status.name : '';
  }

  // Método para verificar si un campo es válido
  isFieldValid(fieldName: string): boolean {
    switch (fieldName) {
      case 'name_task':
        return this.task.name_task.trim().length >= 3;
      case 'desc_task':
        return this.task.desc_task.trim().length >= 10;
      case 'deadline':
        if (!this.task.deadline) return false;
        const selectedDate = new Date(this.task.deadline);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return selectedDate >= today;
      case 'status':
        return this.task.status > 0;
      default:
        return true;
    }
  }

  // Método para obtener el mensaje de error específico de un campo
  getFieldError(fieldName: string): string | null {
    switch (fieldName) {
      case 'name_task':
        if (!this.task.name_task.trim()) return 'El nombre es requerido';
        if (this.task.name_task.trim().length < 3) return 'Mínimo 3 caracteres';
        return null;
      case 'desc_task':
        if (!this.task.desc_task.trim()) return 'La descripción es requerida';
        if (this.task.desc_task.trim().length < 10) return 'Mínimo 10 caracteres';
        return null;
      case 'deadline':
        if (!this.task.deadline) return 'La fecha es requerida';
        const selectedDate = new Date(this.task.deadline);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (selectedDate < today) return 'No puede ser en el pasado';
        return null;
      case 'status':
        if (!this.task.status || this.task.status === 0) return 'Selecciona un estado';
        return null;
      default:
        return null;
    }
  }
}