import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, Users, MessageSquare, BadgeCheck,
  Network, Brain, TrendingUp, CreditCard,
  Headphones, BarChart3, Shield, Bell, Search,
  LogOut, ChevronRight
} from 'lucide-react';
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Badge } from "../ui/badge";
import { Separator } from "../ui/separator";
import Logo from "../../imports/Logo";
import type { AdminInfo } from '../../api/types';

interface MainLayoutProps {
  children: React.ReactNode;
  admin?: AdminInfo | null;
  onLogout?: () => void;
}

const roleLabels: Record<string, string> = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  moderator: 'Moderator',
};

const menuItems = [
  { path: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { path: '/users', label: 'User Center', icon: Users },
  { path: '/content', label: 'Content & Comments', icon: MessageSquare },
  { path: '/verification', label: 'Identity & Verification', icon: BadgeCheck },
  { path: '/social', label: 'Social & Matching', icon: Network },
  { path: '/ai', label: 'AI & Deep Search', icon: Brain },
  { path: '/growth', label: 'Operations & Growth', icon: TrendingUp },
  { path: '/finance', label: 'Payment & Membership', icon: CreditCard },
  { path: '/feedback', label: 'Feedback & Support', icon: Headphones },
  { path: '/reports', label: 'Data Reports', icon: BarChart3 },
  { path: '/system', label: 'System & Logs', icon: Shield },
];

export const MainLayout = ({ children, admin, onLogout }: MainLayoutProps) => {
  const location = useLocation();
  const navigate = useNavigate();

  return (
    <div className="flex h-screen bg-gray-50 font-sans text-slate-900">
      {/* Sidebar */}
      <aside className="w-64 bg-slate-950 text-white flex flex-col flex-shrink-0 border-r border-slate-800 shadow-xl z-20">
        <div className="h-16 flex items-center px-6 border-b border-slate-800">
          <div className="w-8 h-8 mr-3 flex-shrink-0">
            <Logo />
          </div>
          <span className="font-bold text-lg tracking-wider">ICERED ADMIN</span>
        </div>

        <div className="flex-1 overflow-y-auto py-4">
          <nav className="space-y-1 px-3">
            {menuItems.map((item) => {
              const Icon = item.icon;
              const isActive = location.pathname === item.path ||
                               location.pathname.startsWith(item.path + '/');
              return (
                <button
                  key={item.path}
                  onClick={() => navigate(item.path)}
                  className={`w-full flex items-center px-3 py-2.5 text-sm font-medium rounded-md transition-all duration-200 group ${
                    isActive
                      ? 'bg-red-600 text-white shadow-md shadow-red-900/20'
                      : 'text-slate-400 hover:bg-slate-900 hover:text-white'
                  }`}
                >
                  <Icon className={`mr-3 h-5 w-5 ${isActive ? 'text-white' : 'text-slate-500 group-hover:text-white'}`} />
                  {item.label}
                  {isActive && <ChevronRight className="ml-auto h-4 w-4 opacity-50" />}
                </button>
              );
            })}
          </nav>
        </div>

        <div className="p-4 border-t border-slate-800">
          <div className="flex items-center">
            <Avatar className="h-9 w-9 border border-slate-600">
              <AvatarImage src={admin?.avatar || "https://github.com/shadcn.png"} />
              <AvatarFallback>{admin?.name?.slice(0, 2) || 'AD'}</AvatarFallback>
            </Avatar>
            <div className="ml-3">
              <p className="text-sm font-medium text-white">{admin?.name || 'Admin'}</p>
              <p className="text-xs text-slate-500">{admin?.role ? roleLabels[admin.role] : 'User'}</p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="ml-auto text-slate-400 hover:text-white hover:bg-slate-800"
              onClick={onLogout}
              title="Logout"
            >
              <LogOut className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Top Header */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-8 shadow-sm z-10">
          <div className="flex items-center w-96">
            <div className="relative w-full">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
              <Input
                placeholder="Search users, content, orders..."
                className="pl-9 bg-slate-50 border-slate-200 focus-visible:ring-red-500"
              />
            </div>
          </div>

          <div className="flex items-center space-x-4">
            <Button variant="ghost" size="icon" className="relative text-slate-600">
              <Bell className="h-5 w-5" />
              <span className="absolute top-2 right-2 h-2 w-2 bg-red-600 rounded-full ring-2 ring-white"></span>
            </Button>
            <Separator orientation="vertical" className="h-6" />
            <div className="flex items-center text-sm text-slate-600">
              <span className="mr-2">V 2.4.0</span>
              <Badge variant="outline" className="text-xs border-green-500 text-green-600 bg-green-50">System Normal</Badge>
            </div>
          </div>
        </header>

        {/* Page Content */}
        <main className="flex-1 overflow-y-auto p-8 bg-slate-50/50">
          {children}
        </main>
      </div>
    </div>
  );
};
