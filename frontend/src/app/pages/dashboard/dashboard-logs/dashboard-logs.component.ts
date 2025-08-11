import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Chart, ChartConfiguration, registerables } from 'chart.js';
import { ViewChild, ElementRef } from '@angular/core';
import { forkJoin, of } from 'rxjs';
import { catchError, finalize } from 'rxjs/operators';

Chart.register(...registerables);

interface LogStats {
  total_api_calls: number;
  unique_users: number;
  service_statistics: { [key: string]: number };
  status_code_statistics: { [key: string]: number };
  response_time_statistics: { 
    [key: string]: {
      total_calls: number;
      total_ms: number;
      avg_ms: number;
      min_ms: number;
      max_ms: number;
    }
  };
  hourly_stats: { [key: string]: number };
  daily_stats: { [key: string]: number };
  top_endpoints: { endpoint: string; calls: number; avg_response_time: number }[];
  error_rate: number;
  success_rate: number;
}

interface LogEntry {
  timestamp: string;
  method: string;
  endpoint: string;
  status_code: number;
  response_time_ms: number;
  user: string;
  service: string;
}

@Component({
  selector: 'app-dashboard-logs',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-logs.component.html',
  styleUrls: ['./dashboard-logs.component.css']
})
export class DashboardLogsComponent implements OnInit, OnDestroy {
  
  stats: LogStats | null = null;
  recentLogs: LogEntry[] = [];
  loading = true;
  error: string | null = null;
  
  // Charts
  statusCodeChart: Chart | null = null;
  serviceChart: Chart | null = null;
  responseTimeChart: Chart | null = null;
  hourlyTrafficChart: Chart | null = null;
  topEndpointsChart: Chart | null = null;
  errorRateChart: Chart | null = null;

  private apiUrl = 'https://answering-plastic-euro-suited.trycloudflare.com';
  private refreshInterval: any = null;
  private isLoadingData = false; // Flag para evitar llamadas múltiples
  private chartsCreated = false; // Flag para evitar recrear charts innecesariamente

  constructor(private http: HttpClient) { }

  ngOnInit(): void {
    this.loadDashboardData();
    // Remover auto-refresh automático
    // Solo se actualizará cuando el usuario presione el botón
  }

  ngOnDestroy(): void {
    this.clearRefreshInterval();
    this.destroyCharts();
  }

  private clearRefreshInterval(): void {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  loadDashboardData(): void {
    // Evitar múltiples llamadas simultáneas
    if (this.isLoadingData) {
      return;
    }

    this.isLoadingData = true;
    this.loading = true;
    this.error = null;

    // Usar forkJoin para hacer las llamadas en paralelo y optimizar la carga
    const statsRequest = this.http.get<LogStats>(`${this.apiUrl}/logs/stats`).pipe(
      catchError(err => {
        console.error('Error loading stats:', err);
        return of(null);
      })
    );

    const logsRequest = this.http.get<{logs: LogEntry[], total: number}>(`${this.apiUrl}/logs?limit=50`).pipe(
      catchError(err => {
        console.error('Error loading logs:', err);
        return of(null);
      })
    );

    forkJoin({
      stats: statsRequest,
      logs: logsRequest
    }).pipe(
      finalize(() => {
        this.loading = false;
        this.isLoadingData = false;
      })
    ).subscribe({
      next: (response) => {
        if (response.stats) {
          this.stats = response.stats;
          // Solo crear charts si hay datos y no se han creado antes
          if (!this.chartsCreated || this.hasSignificantDataChange()) {
            this.createChartsWithDelay();
          }
        } else {
          this.error = 'Error al cargar estadísticas';
        }

        if (response.logs) {
          this.recentLogs = response.logs.logs;
        } else if (!response.stats) {
          this.error = 'Error al cargar datos del dashboard';
        }
      },
      error: (err) => {
        this.error = 'Error de conexión con el servidor';
        console.error('Dashboard loading error:', err);
      }
    });
  }

  private hasSignificantDataChange(): boolean {
    // Implementar lógica para detectar si hay cambios significativos
    // Por ejemplo, comparar el número total de llamadas
    return true; // Por simplicidad, siempre recrear por ahora
  }

  private createChartsWithDelay(): void {
    // Usar requestAnimationFrame para asegurar que el DOM esté listo
    requestAnimationFrame(() => {
      this.destroyCharts();
      this.createAllCharts();
      this.chartsCreated = true;
    });
  }

  private createAllCharts(): void {
    if (!this.stats) return;

    try {
      this.createStatusCodeChart();
      this.createServiceChart();
      this.createResponseTimeChart();
      this.createHourlyTrafficChart();
      this.createTopEndpointsChart();
      this.createErrorRateChart();
    } catch (error) {
      console.error('Error creating charts:', error);
      this.error = 'Error al crear los gráficos';
    }
  }

  createCharts(): void {
    this.createChartsWithDelay();
  }

  destroyCharts(): void {
    const charts = [
      this.statusCodeChart, 
      this.serviceChart, 
      this.responseTimeChart,
      this.hourlyTrafficChart, 
      this.topEndpointsChart, 
      this.errorRateChart
    ];
    
    charts.forEach(chart => {
      if (chart) {
        try {
          chart.destroy();
        } catch (error) {
          console.error('Error destroying chart:', error);
        }
      }
    });
    
    // Reset all chart references
    this.statusCodeChart = null;
    this.serviceChart = null;
    this.responseTimeChart = null;
    this.hourlyTrafficChart = null;
    this.topEndpointsChart = null;
    this.errorRateChart = null;
    this.chartsCreated = false;
  }

  createStatusCodeChart(): void {
    const ctx = document.getElementById('statusCodeChart') as HTMLCanvasElement;
    if (!ctx || !this.stats) return;

    const labels = Object.keys(this.stats.status_code_statistics);
    const data = Object.values(this.stats.status_code_statistics);
    
    if (labels.length === 0) return; // No crear chart si no hay datos

    const backgroundColors = labels.map(code => {
      if (code.startsWith('2')) return '#10B981';
      if (code.startsWith('3')) return '#F59E0B';
      if (code.startsWith('4')) return '#F97316';
      if (code.startsWith('5')) return '#EF4444';
      return '#6B7280';
    });

    this.statusCodeChart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: labels,
        datasets: [{
          data: data,
          backgroundColor: backgroundColors,
          borderWidth: 2,
          borderColor: '#ffffff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300 // Reducir duración de animación
        },
        plugins: {
          title: {
            display: true,
            text: 'Distribución de Status Codes'
          },
          legend: {
            position: 'bottom'
          },
          tooltip: {
            callbacks: {
              label: function(context) {
                const total = context.dataset.data.reduce((a: any, b: any) => a + b, 0);
                const percentage = ((context.raw as number / total) * 100).toFixed(1);
                return `${context.label}: ${context.raw} (${percentage}%)`;
              }
            }
          }
        }
      }
    });
  }

  createServiceChart(): void {
    const ctx = document.getElementById('serviceChart') as HTMLCanvasElement;
    if (!ctx || !this.stats) return;

    const sortedServices = Object.entries(this.stats.service_statistics)
      .sort(([,a], [,b]) => b - a)
      .slice(0, 10);

    if (sortedServices.length === 0) return;

    const labels = sortedServices.map(([service]) => service.replace('-service', ''));
    const data = sortedServices.map(([,calls]) => calls);

    this.serviceChart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Llamadas por Servicio',
          data: data,
          backgroundColor: [
            '#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6', 
            '#F97316', '#06B6D4', '#84CC16', '#F43F5E', '#6366F1'
          ],
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        plugins: {
          title: {
            display: true,
            text: 'APIs Más Consultadas'
          },
          tooltip: {
            callbacks: {
              afterLabel: function(context) {
                const total = context.dataset.data.reduce((a: any, b: any) => a + b, 0);
                const percentage = ((context.raw as number / total) * 100).toFixed(1);
                return `${percentage}% del total`;
              }
            }
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            title: {
              display: true,
              text: 'Número de Llamadas'
            }
          }
        }
      }
    });
  }

  createResponseTimeChart(): void {
    const ctx = document.getElementById('responseTimeChart') as HTMLCanvasElement;
    if (!ctx || !this.stats) return;

    const services = Object.keys(this.stats.response_time_statistics);
    if (services.length === 0) return;

    const avgTimes = services.map(service => 
      this.stats!.response_time_statistics[service].avg_ms
    );

    this.responseTimeChart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: services.map(s => s.replace('-service', '')),
        datasets: [{
          label: 'Tiempo Promedio (ms)',
          data: avgTimes,
          backgroundColor: '#3B82F6'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        plugins: {
          title: {
            display: true,
            text: 'Tiempos de Respuesta Promedio'
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            title: {
              display: true,
              text: 'Tiempo (ms)'
            }
          }
        }
      }
    });
  }

  createHourlyTrafficChart(): void {
    const ctx = document.getElementById('hourlyTrafficChart') as HTMLCanvasElement;
    if (!ctx || !this.stats?.hourly_stats) return;

    const hours = Object.keys(this.stats.hourly_stats).sort();
    if (hours.length === 0) return;

    const traffic = hours.map(hour => this.stats!.hourly_stats[hour]);

    this.hourlyTrafficChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: hours.map(h => `${h}:00`),
        datasets: [{
          label: 'Tráfico por Hora',
          data: traffic,
          borderColor: '#3B82F6',
          backgroundColor: 'rgba(59, 130, 246, 0.1)',
          fill: true,
          tension: 0.4
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        plugins: {
          title: {
            display: true,
            text: 'Tráfico por Horas (Últimas 24h)'
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            title: {
              display: true,
              text: 'Número de Requests'
            }
          }
        }
      }
    });
  }

  createTopEndpointsChart(): void {
    const ctx = document.getElementById('topEndpointsChart') as HTMLCanvasElement;
    if (!ctx || !this.stats?.top_endpoints) return;

    const endpoints = this.stats.top_endpoints.slice(0, 10);
    if (endpoints.length === 0) return;

    const labels = endpoints.map(ep => this.formatEndpoint(ep.endpoint));
    const calls = endpoints.map(ep => ep.calls);

    this.topEndpointsChart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          label: 'Número de Llamadas',
          data: calls,
          backgroundColor: '#10B981'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        plugins: {
          title: {
            display: true,
            text: 'Top Endpoints Más Utilizados'
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            title: {
              display: true,
              text: 'Número de Llamadas'
            }
          }
        }
      }
    });
  }

  createErrorRateChart(): void {
    const ctx = document.getElementById('errorRateChart') as HTMLCanvasElement;
    if (!ctx || !this.stats) return;

    const successRate = this.stats.success_rate;
    const errorRate = this.stats.error_rate;

    this.errorRateChart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: ['Exitosas', 'Con Error'],
        datasets: [{
          data: [successRate, errorRate],
          backgroundColor: ['#10B981', '#EF4444'],
          borderWidth: 2,
          borderColor: '#ffffff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        plugins: {
          title: {
            display: true,
            text: 'Tasa de Éxito vs Error'
          },
          legend: {
            position: 'bottom'
          },
          tooltip: {
            callbacks: {
              label: function(context) {
                return `${context.label}: ${(context.raw as number).toFixed(1)}%`;
              }
            }
          }
        }
      }
    });
  }

  // Método para refresh manual solamente
  refreshData(): void {
    this.loadDashboardData();
  }

  // Método para habilitar auto-refresh (opcional)
  enableAutoRefresh(intervalSeconds: number = 30): void {
    this.clearRefreshInterval();
    this.refreshInterval = setInterval(() => {
      this.loadDashboardData();
    }, intervalSeconds * 1000);
  }

  // Método para deshabilitar auto-refresh
  disableAutoRefresh(): void {
    this.clearRefreshInterval();
  }

  // Resto de métodos auxiliares (sin cambios significativos)
  downloadLogs(): void {
    window.open(`${this.apiUrl}/logs/download`, '_blank');
  }

  getStatusBadgeClass(statusCode: number): string {
    if (statusCode >= 200 && statusCode < 300) return 'badge-success';
    if (statusCode >= 300 && statusCode < 400) return 'badge-warning';
    if (statusCode >= 400 && statusCode < 500) return 'badge-error';
    if (statusCode >= 500) return 'badge-critical';
    return 'badge-default';
  }

  formatTimestamp(timestamp: string): string {
    return new Date(timestamp).toLocaleString('es-ES', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }

  formatEndpoint(endpoint: string): string {
    const parts = endpoint.split('/');
    return parts.length > 3 ? '.../' + parts.slice(-2).join('/') : endpoint;
  }

  // Métodos de estadísticas (sin cambios)
  getAverageResponseTime(): number {
    if (!this.stats) return 0;
    
    const services = Object.values(this.stats.response_time_statistics);
    const totalTime = services.reduce((sum, service) => sum + service.total_ms, 0);
    const totalCalls = services.reduce((sum, service) => sum + service.total_calls, 0);
    
    return totalCalls > 0 ? Math.round(totalTime / totalCalls) : 0;
  }

  getSlowestAPI(): string {
    if (!this.stats) return 'N/A';
    
    const services = Object.entries(this.stats.response_time_statistics);
    if (services.length === 0) return 'N/A';
    
    const slowest = services.reduce((prev, current) => 
      prev[1].avg_ms > current[1].avg_ms ? prev : current
    );
    
    return slowest[0].replace('-service', '');
  }

  getFastestAPI(): string {
    if (!this.stats) return 'N/A';
    
    const services = Object.entries(this.stats.response_time_statistics);
    if (services.length === 0) return 'N/A';
    
    const fastest = services.reduce((prev, current) => 
      prev[1].avg_ms < current[1].avg_ms ? prev : current
    );
    
    return fastest[0].replace('-service', '');
  }

  getSlowestResponseTime(): number {
    if (!this.stats) return 0;
    
    const services = Object.entries(this.stats.response_time_statistics);
    if (services.length === 0) return 0;
    
    const slowest = services.reduce((prev, current) => 
      prev[1].avg_ms > current[1].avg_ms ? prev : current
    );
    
    return Math.round(slowest[1].avg_ms);
  }

  getFastestResponseTime(): number {
    if (!this.stats) return 0;
    
    const services = Object.entries(this.stats.response_time_statistics);
    if (services.length === 0) return 0;
    
    const fastest = services.reduce((prev, current) => 
      prev[1].avg_ms < current[1].avg_ms ? prev : current
    );
    
    return Math.round(fastest[1].avg_ms);
  }

  getMostUsedAPI(): string {
    if (!this.stats) return 'N/A';
    
    const services = Object.entries(this.stats.service_statistics);
    if (services.length === 0) return 'N/A';
    
    const mostUsed = services.reduce((prev, current) => 
      prev[1] > current[1] ? prev : current
    );
    
    return mostUsed[0].replace('-service', '');
  }

  getLeastUsedAPI(): string {
    if (!this.stats) return 'N/A';
    
    const services = Object.entries(this.stats.service_statistics);
    if (services.length === 0) return 'N/A';
    
    const leastUsed = services.reduce((prev, current) => 
      prev[1] < current[1] ? prev : current
    );
    
    return leastUsed[0].replace('-service', '');
  }

  getMostUsedAPICount(): number {
    if (!this.stats) return 0;
    
    const services = Object.entries(this.stats.service_statistics);
    if (services.length === 0) return 0;
    
    const mostUsed = services.reduce((prev, current) => 
      prev[1] > current[1] ? prev : current
    );
    
    return mostUsed[1];
  }

  getLeastUsedAPICount(): number {
    if (!this.stats) return 0;
    
    const services = Object.entries(this.stats.service_statistics);
    if (services.length === 0) return 0;
    
    const leastUsed = services.reduce((prev, current) => 
      prev[1] < current[1] ? prev : current
    );
    
    return leastUsed[1];
  }

  Object = Object;
}