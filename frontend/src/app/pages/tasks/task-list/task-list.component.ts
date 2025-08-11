import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CardModule } from 'primeng/card';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { DialogModule } from 'primeng/dialog';
import { InputTextModule } from 'primeng/inputtext';
import { DropdownModule } from 'primeng/dropdown';
import { CalendarModule } from 'primeng/calendar';
import { FormsModule } from '@angular/forms';
import { DragDropModule } from 'primeng/dragdrop';
import { Router } from '@angular/router';
import { MessageService } from 'primeng/api';
import { ToastModule } from 'primeng/toast';

interface Task {
  id_task: number;
  name_task: string;
  desc_task: string;
  status: string;
  deadline: string;
  created_of: string;
  Created_by: string;
  isActive: boolean;
}

interface Status {
  id: number;
  name: string;
}

@Component({
  selector: 'app-task-list',
  standalone: true,
  imports: [
    CommonModule,
    CardModule,
    ButtonModule,
    TagModule,
    DialogModule,
    InputTextModule,
    DropdownModule,
    CalendarModule,
    FormsModule,
    DragDropModule,
    ToastModule
  ],
  providers: [MessageService],
  templateUrl: './task-list.component.html',
  styleUrl: './task-list.component.css'
})
export class TaskListComponent implements OnInit {
  tasks: Task[] = [];
  inProgressTasks: Task[] = [];
  revisionTasks: Task[] = [];
  completedTasks: Task[] = [];
  pausedTasks: Task[] = [];
  
  statusList: Status[] = [
    { id: 1, name: 'In progress' },
    { id: 2, name: 'Revision' },
    { id: 3, name: 'Completed' },
    { id: 4, name: 'Paused' }
  ];
  
  showTaskDialog = false;
  isEditMode = false;
  currentTask: Task = this.getEmptyTask();
  loading = false;
  
  // URL base del API Gateway
  private apiUrl = 'https://answering-plastic-euro-suited.trycloudflare.com';
  
  constructor(
    private router: Router,
    private messageService: MessageService
  ) {}
  
  ngOnInit() {
    this.checkAuthentication();
    this.loadTasks();
  }

  private checkAuthentication(): boolean {
    const token = localStorage.getItem('token');
    if (!token) {
      this.showError('No se encontró token de autenticación. Redirigiendo al login...');
      this.router.navigate(['/login']);
      return false;
    }
    return true;
  }

  private getAuthHeaders(): HeadersInit {
    const token = localStorage.getItem('token');
    return {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    };
  }

  private async handleApiResponse(response: Response): Promise<any> {
    if (response.status === 401 || response.status === 403) {
      this.showError('Sesión expirada. Redirigiendo al login...');
      localStorage.removeItem('token');
      this.router.navigate(['/login']);
      throw new Error('Unauthorized');
    }
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    return await response.json();
  }

  async loadTasks() {
    if (!this.checkAuthentication()) return;
    
    this.loading = true;
    try {
      const response = await fetch(`${this.apiUrl}/tasks`, {
        headers: this.getAuthHeaders()
      });
      
      const data = await this.handleApiResponse(response);
      this.tasks = data.tasks || [];
      this.organizeTasks();
      
    } catch (error) {
      console.error('Error loading tasks:', error);
      if (error instanceof Error && error.message !== 'Unauthorized') {
        this.showError('Error al cargar las tareas. Verifique su conexión.');
      }
    } finally {
      this.loading = false;
    }
  }

  organizeTasks() {
    this.inProgressTasks = this.tasks.filter(task => task.status === 'In progress');
    this.revisionTasks = this.tasks.filter(task => task.status === 'Revision');
    this.completedTasks = this.tasks.filter(task => task.status === 'Completed');
    this.pausedTasks = this.tasks.filter(task => task.status === 'Paused');
  }

  getEmptyTask(): Task {
    return {
      id_task: 0,
      name_task: '',
      desc_task: '',
      status: 'In progress',
      deadline: '',
      created_of: '',
      Created_by: '',
      isActive: true
    };
  }

  openNewTaskDialog() {
  this.router.navigate(['/tasks/create']);
}


  editTask(task: Task) {
    this.currentTask = { ...task };
    this.isEditMode = true;
    this.showTaskDialog = true;
  }

  async saveTask() {
    if (!this.checkAuthentication()) return;
    
    try {
      const statusId = this.statusList.find(s => s.name === this.currentTask.status)?.id || 1;
      
      const taskData = {
        name_task: this.currentTask.name_task,
        desc_task: this.currentTask.desc_task,
        deadline: this.currentTask.deadline,
        status: statusId,
        isActive: this.currentTask.isActive
      };

      let response;
      if (this.isEditMode) {
        response = await fetch(`${this.apiUrl}/tasks/${this.currentTask.id_task}`, {
          method: 'PUT',
          headers: this.getAuthHeaders(),
          body: JSON.stringify(taskData)
        });
      } else {
        response = await fetch(`${this.apiUrl}/tasks`, {
          method: 'POST',
          headers: this.getAuthHeaders(),
          body: JSON.stringify(taskData)
        });
      }

      await this.handleApiResponse(response);
      this.showTaskDialog = false;
      this.showSuccess(this.isEditMode ? 'Tarea actualizada correctamente' : 'Tarea creada correctamente');
      this.loadTasks();
      
    } catch (error) {
      console.error('Error saving task:', error);
      if (error instanceof Error && error.message !== 'Unauthorized') {
        this.showError('Error al guardar la tarea');
      }
    }
  }

  async deleteTask(task: Task) {
    if (!confirm(`¿Estás seguro de eliminar la tarea "${task.name_task}"?`)) {
      return;
    }
    
    if (!this.checkAuthentication()) return;
    
    try {
      const response = await fetch(`${this.apiUrl}/tasks/${task.id_task}`, {
        method: 'DELETE',
        headers: this.getAuthHeaders()
      });

      await this.handleApiResponse(response);
      this.showSuccess('Tarea eliminada correctamente');
      this.loadTasks();
      
    } catch (error) {
      console.error('Error deleting task:', error);
      if (error instanceof Error && error.message !== 'Unauthorized') {
        this.showError('Error al eliminar la tarea');
      }
    }
  }

  async moveTask(task: Task, newStatus: string) {
    const statusId = this.statusList.find(s => s.name === newStatus)?.id;
    if (!statusId || !this.checkAuthentication()) return;

    try {
      const response = await fetch(`${this.apiUrl}/tasks/${task.id_task}`, {
        method: 'PUT',
        headers: this.getAuthHeaders(),
        body: JSON.stringify({ status: statusId })
      });

      await this.handleApiResponse(response);
      this.loadTasks();
      
    } catch (error) {
      console.error('Error moving task:', error);
      if (error instanceof Error && error.message !== 'Unauthorized') {
        this.showError('Error al mover la tarea');
      }
    }
  }

  getStatusSeverity(status: string): string {
    switch (status) {
      case 'In progress': return 'info';
      case 'Revision': return 'warn';
      case 'Completed': return 'success';
      case 'Paused': return 'secondary';
      default: return 'info';
    }
  }

  formatDate(dateString: string): string {
    return new Date(dateString).toLocaleDateString('es-ES');
  }

  isOverdue(deadline: string): boolean {
    return new Date(deadline) < new Date();
  }

  private showError(message: string) {
    this.messageService.add({
      severity: 'error',
      summary: 'Error',
      detail: message
    });
  }

  private showSuccess(message: string) {
    this.messageService.add({
      severity: 'success',
      summary: 'Éxito',
      detail: message
    });
  }

  logout() {
    localStorage.removeItem('token');
    this.router.navigate(['/login']);
  }
}