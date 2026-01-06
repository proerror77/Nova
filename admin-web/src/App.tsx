import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'sonner';
import { MainLayout } from './components/layout/MainLayout';
import { Dashboard } from './components/pages/Dashboard';
import { UserCenter } from './components/pages/UserCenter';
import { ContentManagement } from './components/pages/ContentManagement';
import { VerificationCenter } from './components/pages/VerificationCenter';
import { SocialMatching } from './components/pages/SocialMatching';
import { AIManagement } from './components/pages/AIManagement';
import { OperationsGrowth } from './components/pages/OperationsGrowth';
import { PaymentMembership } from './components/pages/PaymentMembership';
import { FeedbackSupport } from './components/pages/FeedbackSupport';
import { DataReports } from './components/pages/DataReports';
import { SystemLogs } from './components/pages/SystemLogs';
import { Login } from './components/pages/Login';
import { useAuthStore } from './stores/authStore';
import { ErrorBoundary } from './components/common/ErrorBoundary';

// Create a client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

// Protected Route wrapper
function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated } = useAuthStore();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}

export default function App() {
  const { isAuthenticated, login, logout, admin } = useAuthStore();

  return (
    <QueryClientProvider client={queryClient}>
      <ErrorBoundary>
        <BrowserRouter>
          <Toaster position="top-right" richColors />
          <Routes>
            {/* Public routes */}
            <Route
              path="/login"
              element={
                isAuthenticated ? (
                  <Navigate to="/" replace />
                ) : (
                  <Login onLogin={login} />
                )
              }
            />

            {/* Protected routes */}
            <Route
              path="/*"
              element={
                <ProtectedRoute>
                  <MainLayout admin={admin} onLogout={logout}>
                    <Routes>
                      <Route path="/" element={<Navigate to="/dashboard" replace />} />
                      <Route path="/dashboard" element={<Dashboard />} />
                      <Route path="/users" element={<UserCenter />} />
                      <Route path="/users/:id" element={<UserCenter />} />
                      <Route path="/content" element={<ContentManagement />} />
                      <Route path="/verification" element={<VerificationCenter />} />
                      <Route path="/social" element={<SocialMatching />} />
                      <Route path="/ai" element={<AIManagement />} />
                      <Route path="/growth" element={<OperationsGrowth />} />
                      <Route path="/finance" element={<PaymentMembership />} />
                      <Route path="/feedback" element={<FeedbackSupport />} />
                      <Route path="/reports" element={<DataReports />} />
                      <Route path="/system" element={<SystemLogs />} />
                      {/* Catch all - redirect to dashboard */}
                      <Route path="*" element={<Navigate to="/dashboard" replace />} />
                    </Routes>
                  </MainLayout>
                </ProtectedRoute>
              }
            />
          </Routes>
        </BrowserRouter>
      </ErrorBoundary>
    </QueryClientProvider>
  );
}
