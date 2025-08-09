import { Component } from '@angular/core';
import { RouterModule, Router } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-error-404',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './error-404.component.html',
  styleUrls: ['./error-404.component.css']
})
export class Error404Component {
  
  constructor(private router: Router) {}

  goHome() {
    this.router.navigate(['/login']);
  }

  goBack() {
    window.history.back();
  }
}