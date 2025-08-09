import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface Task {
  id: number;
  name: string;
  description: string;
  status: string;
}

@Injectable({
  providedIn: 'root'
})
export class TasksService {

  private apiUrl = 'http://localhost:5000/tasks'; // URL del API Gateway para tareas

  constructor(private http: HttpClient) { }

  getTasks(): Observable<Task[]> {
    return this.http.get<Task[]>(this.apiUrl);
  }
}
