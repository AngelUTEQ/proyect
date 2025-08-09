// src/app/pages/dashboard/dashboard.routes.ts
import { Routes } from '@angular/router';
import { DashboardLogsComponent } from '../dashboard-logs/dashboard-logs.component'; // ruta ajustada

export const dashboardRoutes: Routes = [
  {
    path: '',
    component: DashboardLogsComponent
  }
];
