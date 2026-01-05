import React, { useState } from 'react';
import { MainLayout } from './components/layout/MainLayout';
import { Dashboard } from './components/pages/Dashboard';
import { UserCenter } from './components/pages/UserCenter';
import { ContentManage } from './components/pages/ContentManage';
import { Login } from './components/pages/Login';
import { useAuthStore } from './stores/authStore';

export default function App() {
  const [currentPage, setCurrentPage] = useState('dashboard');
  const { isAuthenticated, login, logout, admin } = useAuthStore();

  const renderPage = () => {
    switch (currentPage) {
      case 'dashboard':
        return <Dashboard />;
      case 'users':
        return <UserCenter />;
      case 'content':
        return <ContentManage />;
      case 'verification':
        return <PlaceholderPage title="身份 & 职业认证" description="审核用户身份证、职业资质等认证材料" />;
      case 'social':
        return <PlaceholderPage title="社交关系 & 匹配管理" description="监控用户社交行为与匹配算法效果" />;
      case 'ai':
        return <PlaceholderPage title="AI & Deepsearch 管理" description="配置AI审核规则与Deepsearch推荐参数" />;
      case 'growth':
        return <PlaceholderPage title="运营 & 增长" description="推广活动、优惠券、增长漏斗分析" />;
      case 'finance':
        return <PlaceholderPage title="支付 & 会员" description="订单管理、会员权益与财务报表" />;
      case 'feedback':
        return <PlaceholderPage title="用户反馈 & 客服" description="处理用户工单、反馈建议与投诉" />;
      case 'reports':
        return <PlaceholderPage title="数据报表中心" description="多维度数据分析与BI看板" />;
      case 'system':
        return <PlaceholderPage title="系统权限 & 操作日志" description="管理员权限配置与系统操作审计" />;
      default:
        return <Dashboard />;
    }
  };

  // Show login page if not authenticated
  if (!isAuthenticated) {
    return <Login onLogin={login} />;
  }

  return (
    <MainLayout
      currentPage={currentPage}
      onNavigate={setCurrentPage}
      admin={admin}
      onLogout={logout}
    >
      {renderPage()}
    </MainLayout>
  );
}

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
