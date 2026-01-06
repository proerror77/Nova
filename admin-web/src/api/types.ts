// API Types - matches backend response structures

// Auth
export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  admin: AdminInfo;
}

export interface AdminInfo {
  id: string;
  email: string;
  name: string;
  role: 'super_admin' | 'admin' | 'moderator' | 'viewer';
  avatar?: string;
}

export interface RefreshRequest {
  refresh_token: string;
}

export interface RefreshResponse {
  access_token: string;
}

// Dashboard
export interface DashboardStats {
  total_users: number;
  active_users_today: number;
  new_users_today: number;
  new_users_change: number;
  verified_users_today: number;
  verified_users_change: number;
  new_comments_today: number;
  new_comments_change: number;
  matches_today: number;
  matches_change: number;
  dau: number;
  dau_change: number;
  banned_users: number;
  banned_today: number;
  total_warnings: number;
  pending_reviews: number;
  admin_actions_today: number;
}

export interface UserChartDataPoint {
  date: string;
  active_users: number;
  new_users: number;
}

export interface UserChartResponse {
  period: string;
  data: UserChartDataPoint[];
}

export interface ActivityChartDataPoint {
  date: string;
  posts: number;
  comments: number;
  likes: number;
}

export interface ActivityChartResponse {
  period: string;
  data: ActivityChartDataPoint[];
}

export interface RecentActivity {
  id: string;
  action: string;
  resource_type: string;
  resource_id?: string;
  created_at: string;
  admin_name: string;
  admin_email: string;
}

export interface RiskAlert {
  id: string;
  level: 'high' | 'medium' | 'low';
  title: string;
  description: string;
  value: number;
  user_id?: string;
  created_at: string;
}

export interface RiskAlertsResponse {
  items: RiskAlert[];
  total: number;
}

// Users
export interface User {
  id: string;
  nickname: string;
  email: string;
  phone?: string;
  avatar?: string;
  bio?: string;
  status: string;
  is_banned: boolean;
  warnings_count: number;
  created_at: string;
  updated_at: string;
  last_active_at?: string;
}

export interface UserListResponse {
  users: UserSummary[];
  total: number;
  page: number;
  limit: number;
}

export interface UserSummary {
  id: string;
  nickname: string;
  email: string;
  avatar?: string;
  status: string;
  created_at: string;
  last_active_at?: string;
}

export interface UserHistoryResponse {
  bans: BanHistory[];
  warnings: WarningHistory[];
}

export interface BanHistory {
  id: string;
  reason: string;
  duration_days?: number;
  banned_at: string;
  expires_at?: string;
  is_active: boolean;
}

export interface WarningHistory {
  id: string;
  reason: string;
  severity: 'low' | 'medium' | 'high';
  created_at: string;
}

export interface BanUserRequest {
  reason: string;
  duration_days?: number;
}

export interface WarnUserRequest {
  reason: string;
  severity?: 'low' | 'medium' | 'high';
}

// Content
export interface Post {
  id: string;
  author_id: string;
  content_preview: string;
  status: string;
  images_count: number;
  likes_count: number;
  comments_count: number;
  reports_count: number;
  created_at: string;
}

export interface PostListResponse {
  posts: Post[];
  total: number;
  page: number;
  limit: number;
}

export interface PostDetail {
  id: string;
  author?: AuthorInfo;
  content: string;
  images: string[];
  status: string;
  stats: PostStats;
  reports: ReportSummary[];
  created_at: string;
  updated_at: string;
}

export interface AuthorInfo {
  id: string;
  nickname: string;
  avatar?: string;
  warnings_count: number;
  is_banned: boolean;
}

export interface PostStats {
  likes_count: number;
  comments_count: number;
  shares_count: number;
  reports_count: number;
}

export interface ReportSummary {
  id: string;
  reason: string;
  reporter_id: string;
  status: string;
  created_at: string;
}

export interface Comment {
  id: string;
  post_id: string;
  author_id: string;
  content: string;
  status: string;
  reports_count: number;
  created_at: string;
}

export interface CommentListResponse {
  comments: Comment[];
  total: number;
  page: number;
  limit: number;
}

export interface ModerationRequest {
  notes?: string;
}

export interface RejectRequest {
  reason: string;
  notes?: string;
}

// Common
export interface ApiError {
  code: string;
  message: string;
  request_id?: string;
  details?: Record<string, unknown>;
}

export interface PaginationParams {
  page?: number;
  limit?: number;
  status?: string;
  search?: string;
}
