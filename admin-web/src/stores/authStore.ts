import { create } from 'zustand';
import { persist } from 'zustand/middleware';

// API base URL - uses relative path for same-origin requests via ingress
const API_BASE_URL = '/api/admin/v1';

interface Admin {
  id: string;
  email: string;
  name: string;
  role: 'super_admin' | 'admin' | 'moderator';
  avatar?: string;
}

interface AuthState {
  admin: Admin | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => void;
  getAuthHeader: () => Record<string, string>;
}

interface LoginResponse {
  access_token: string;
  refresh_token: string;
  admin: Admin;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      admin: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,

      login: async (email: string, password: string): Promise<boolean> => {
        try {
          const response = await fetch(`${API_BASE_URL}/auth/login`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ email, password }),
          });

          if (!response.ok) {
            return false;
          }

          const data: LoginResponse = await response.json();
          set({
            admin: data.admin,
            accessToken: data.access_token,
            refreshToken: data.refresh_token,
            isAuthenticated: true,
          });
          return true;
        } catch (error) {
          console.error('Login failed:', error);
          return false;
        }
      },

      logout: () => {
        const { accessToken } = get();
        if (accessToken) {
          fetch(`${API_BASE_URL}/auth/logout`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          }).catch(() => {});
        }
        set({ admin: null, accessToken: null, refreshToken: null, isAuthenticated: false });
      },

      getAuthHeader: (): Record<string, string> => {
        const { accessToken } = get();
        if (accessToken) {
          return { 'Authorization': `Bearer ${accessToken}` };
        }
        return {};
      },
    }),
    {
      name: 'admin-auth',
      partialize: (state) => ({
        admin: state.admin,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
);
