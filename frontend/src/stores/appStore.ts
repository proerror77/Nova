import { create } from 'zustand';

type AppState = {
  online: boolean;
  setOnline: (online: boolean) => void;
  theme: 'light' | 'dark';
  setTheme: (theme: 'light' | 'dark') => void;
  ready: boolean;
  setReady: (ready: boolean) => void;
};

export const useAppStore = create<AppState>((set) => ({
  online: true,
  setOnline: (online) => set({ online }),
  theme: (localStorage.getItem('app:theme') as 'light' | 'dark') || 'light',
  setTheme: (theme) => {
    localStorage.setItem('app:theme', theme);
    set({ theme });
  },
  ready: false,
  setReady: (ready) => set({ ready }),
}));

