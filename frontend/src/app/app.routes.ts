import { Routes } from '@angular/router';
import { LoginComponent } from './pages/auth/login/login.component';
import { RegisterComponent } from './pages/auth/register/register.component';
import { TaskListComponent } from './pages/tasks/task-list/task-list.component';
import { TaskCreateComponent } from './pages/tasks/task-create/task-create.component';
import { Error404Component } from './pages/errors/error-404/error-404.component';

export const routes: Routes = [
  { path: '', redirectTo: '/login', pathMatch: 'full' },
  { path: 'login', component: LoginComponent },
  { path: 'register', component: RegisterComponent },
  { path: 'tasks', component: TaskListComponent },
  { path: 'tasks/create', component: TaskCreateComponent },
  {
    path: 'dashboard',
    loadComponent: () =>
      import('./pages/dashboard/dashboard-logs/dashboard-logs.component').then(m => m.DashboardLogsComponent)
  },
  { path: '404', component: Error404Component },
  { path: '**', redirectTo: '/404' }
];
