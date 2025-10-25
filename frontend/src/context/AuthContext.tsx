import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';

type AuthState = {
  accessToken: string | null;
  setAccessToken: (token: string | null) => void;
  refreshToken: string | null;
  setRefreshToken: (token: string | null) => void;
  userId: string | null;
  setUserId: (id: string | null) => void;
};

const AuthContext = createContext<AuthState | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [accessToken, setAccessToken] = useState<string | null>(() => localStorage.getItem('auth:accessToken'));
  const [refreshToken, setRefreshToken] = useState<string | null>(() => localStorage.getItem('auth:refreshToken'));
  const [userId, setUserId] = useState<string | null>(() => localStorage.getItem('auth:userId'));

  useEffect(() => {
    if (accessToken) localStorage.setItem('auth:accessToken', accessToken);
    else localStorage.removeItem('auth:accessToken');
  }, [accessToken]);

  useEffect(() => {
    if (refreshToken) localStorage.setItem('auth:refreshToken', refreshToken);
    else localStorage.removeItem('auth:refreshToken');
  }, [refreshToken]);

  useEffect(() => {
    if (userId) localStorage.setItem('auth:userId', userId);
    else localStorage.removeItem('auth:userId');
  }, [userId]);

  const value = useMemo(
    () => ({ accessToken, setAccessToken, refreshToken, setRefreshToken, userId, setUserId }),
    [accessToken, refreshToken, userId]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

