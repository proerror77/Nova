import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface Admin {
  id: string;
  email: string;
  name: string;
  role: 'super_admin' | 'admin' | 'moderator';
  avatar?: string;
}

interface AuthState {
  admin: Admin | null;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => void;
}

// Mock admin accounts for development
const MOCK_ADMINS: Record<string, { password: string; admin: Admin }> = {
  'admin@nova.app': {
    password: 'admin123',
    admin: {
      id: '1',
      email: 'admin@nova.app',
      name: '系统管理员',
      role: 'super_admin',
    },
  },
  'mod@nova.app': {
    password: 'mod123',
    admin: {
      id: '2',
      email: 'mod@nova.app',
      name: '内容审核员',
      role: 'moderator',
    },
  },
};

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      admin: null,
      isAuthenticated: false,

      login: async (email: string, password: string): Promise<boolean> => {
        // Simulate network delay
        await new Promise((resolve) => setTimeout(resolve, 800));

        const mockAccount = MOCK_ADMINS[email.toLowerCase()];
        if (mockAccount && mockAccount.password === password) {
          set({ admin: mockAccount.admin, isAuthenticated: true });
          return true;
        }
        return false;
      },

      logout: () => {
        set({ admin: null, isAuthenticated: false });
      },
    }),
    {
      name: 'admin-auth',
      partialize: (state) => ({ admin: state.admin, isAuthenticated: state.isAuthenticated }),
    }
  )
);
