import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { authApi, setTokens, clearTokens, getAccessToken } from '../api';
import type { AdminInfo } from '../api/types';

interface AuthState {
  admin: AdminInfo | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  checkAuth: () => Promise<boolean>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      admin: null,
      isAuthenticated: false,
      isLoading: false,

      login: async (email: string, password: string): Promise<boolean> => {
        set({ isLoading: true });
        try {
          const response = await authApi.login({ email, password });
          set({
            admin: response.admin,
            isAuthenticated: true,
            isLoading: false,
          });
          return true;
        } catch (error) {
          set({ isLoading: false });
          console.error('Login failed:', error);
          return false;
        }
      },

      logout: async () => {
        try {
          await authApi.logout();
        } catch (error) {
          console.error('Logout error:', error);
        } finally {
          clearTokens();
          set({ admin: null, isAuthenticated: false });
        }
      },

      checkAuth: async (): Promise<boolean> => {
        const token = getAccessToken();
        if (!token) {
          set({ admin: null, isAuthenticated: false });
          return false;
        }

        try {
          const admin = await authApi.me();
          set({ admin, isAuthenticated: true });
          return true;
        } catch (error) {
          clearTokens();
          set({ admin: null, isAuthenticated: false });
          return false;
        }
      },
    }),
    {
      name: 'admin-auth',
      partialize: (state) => ({
        admin: state.admin,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
);
