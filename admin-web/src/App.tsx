import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'sonner';
import { MainLayout } from './components/layout/MainLayout';
import { Dashboard } from './components/pages/Dashboard';
import { UserCenter } from './components/pages/UserCenter';
import { ContentManage } from './components/pages/ContentManage';
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

// Placeholder page component
const PlaceholderPage = ({ title, description }: { title: string; description: string }) => (
  <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
    <div>
      <h2 className="text-3xl font-bold tracking-tight text-slate-900">{title}</h2>
      <p className="text-slate-500 mt-1">{description}</p>
    </div>
    <div className="bg-white border border-slate-200 rounded-lg p-12 text-center">
      <div className="text-slate-400 text-lg">此页面待开发</div>
      <div className="text-slate-500 text-sm mt-2">敬请期待...</div>
    </div>
  </div>
);

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
                      <Route path="/content" element={<ContentManage />} />
                      <Route
                        path="/verification"
                        element={
                          <PlaceholderPage
                            title="身份 & 职业认证"
                            description="审核用户身份证、职业资质等认证材料"
                          />
                        }
                      />
                      <Route
                        path="/social"
                        element={
                          <PlaceholderPage
                            title="社交关系 & 匹配管理"
                            description="监控用户社交行为与匹配算法效果"
                          />
                        }
                      />
                      <Route
                        path="/ai"
                        element={
                          <PlaceholderPage
                            title="AI & Deepsearch 管理"
                            description="配置AI审核规则与Deepsearch推荐参数"
                          />
                        }
                      />
                      <Route
                        path="/growth"
                        element={
                          <PlaceholderPage
                            title="运营 & 增长"
                            description="推广活动、优惠券、增长漏斗分析"
                          />
                        }
                      />
                      <Route
                        path="/finance"
                        element={
                          <PlaceholderPage
                            title="支付 & 会员"
                            description="订单管理、会员权益与财务报表"
                          />
                        }
                      />
                      <Route
                        path="/feedback"
                        element={
                          <PlaceholderPage
                            title="用户反馈 & 客服"
                            description="处理用户工单、反馈建议与投诉"
                          />
                        }
                      />
                      <Route
                        path="/reports"
                        element={
                          <PlaceholderPage
                            title="数据报表中心"
                            description="多维度数据分析与BI看板"
                          />
                        }
                      />
                      <Route
                        path="/system"
                        element={
                          <PlaceholderPage
                            title="系统权限 & 操作日志"
                            description="管理员权限配置与系统操作审计"
                          />
                        }
                      />
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
