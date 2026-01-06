import React from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Users, UserCheck, MessageCircle, Heart, Activity, AlertTriangle, Loader2 } from "lucide-react";
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { useDashboardStats, useUserChart, useRiskAlerts } from '../../hooks';

interface StatCardProps {
  title: string;
  value: string | number;
  sub: string;
  icon: React.ElementType;
  trend: 'up' | 'down';
  isLoading?: boolean;
}

const StatCard = ({ title, value, sub, icon: Icon, trend, isLoading }: StatCardProps) => (
  <Card>
    <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
      <CardTitle className="text-sm font-medium text-slate-500">{title}</CardTitle>
      <Icon className="h-4 w-4 text-slate-400" />
    </CardHeader>
    <CardContent>
      {isLoading ? (
        <div className="flex items-center space-x-2">
          <Loader2 className="h-5 w-5 animate-spin text-slate-400" />
          <span className="text-slate-400">Loading...</span>
        </div>
      ) : (
        <>
          <div className="text-2xl font-bold">{typeof value === 'number' ? value.toLocaleString() : value}</div>
          <p className={`text-xs ${trend === 'up' ? 'text-green-500' : 'text-red-500'} flex items-center mt-1`}>
            {sub}
          </p>
        </>
      )}
    </CardContent>
  </Card>
);

const formatNumber = (num: number): string => {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
};

export const Dashboard = () => {
  const { data: stats, isLoading: statsLoading, error: statsError } = useDashboardStats();
  const { data: chartData, isLoading: chartLoading } = useUserChart('7d');
  const { data: riskAlerts, isLoading: alertsLoading } = useRiskAlerts();

  // Transform chart data for recharts
  const chartDataFormatted = chartData?.data?.map(item => ({
    name: new Date(item.date).toLocaleDateString('en-US', { weekday: 'short' }),
    active: item.active_users,
    new: item.new_users,
  })) || [];

  // Get risk level color
  const getRiskColor = (level: string) => {
    switch (level) {
      case 'high': return 'text-red-600';
      case 'medium': return 'text-yellow-600';
      case 'low': return 'text-green-600';
      default: return 'text-slate-600';
    }
  };

  const getRiskBarColor = (level: string) => {
    switch (level) {
      case 'high': return 'bg-red-600';
      case 'medium': return 'bg-yellow-500';
      case 'low': return 'bg-green-500';
      default: return 'bg-slate-400';
    }
  };

  return (
    <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
      <div className="flex justify-between items-end">
        <div>
          <h2 className="text-3xl font-bold tracking-tight text-slate-900">Dashboard</h2>
          <p className="text-slate-500 mt-1">Icered Admin Real-time Data Monitoring Center</p>
        </div>
        {riskAlerts?.items?.some(a => a.level === 'high') && (
          <div className="flex space-x-2">
            <div className="bg-red-50 text-red-700 px-3 py-1 rounded text-sm font-medium border border-red-100 flex items-center">
              <AlertTriangle className="w-4 h-4 mr-2"/>
              {riskAlerts.items.filter(a => a.level === 'high').length} High Risk Alerts
            </div>
          </div>
        )}
      </div>

      {statsError && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          Unable to load statistics. Please try again later.
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
        <StatCard
          title="New Registered Users"
          value={stats?.new_users_today || 0}
          sub={`${stats?.new_users_change && stats.new_users_change >= 0 ? '+' : ''}${stats?.new_users_change?.toFixed(1) || 0}% vs yesterday`}
          trend={stats?.new_users_change && stats.new_users_change >= 0 ? 'up' : 'down'}
          icon={Users}
          isLoading={statsLoading}
        />
        <StatCard
          title="New Verified Users"
          value={stats?.verified_users_today || 0}
          sub={`${stats?.verified_users_change && stats.verified_users_change >= 0 ? '+' : ''}${stats?.verified_users_change?.toFixed(1) || 0}% vs yesterday`}
          trend={stats?.verified_users_change && stats.verified_users_change >= 0 ? 'up' : 'down'}
          icon={UserCheck}
          isLoading={statsLoading}
        />
        <StatCard
          title="New Comments"
          value={stats?.new_comments_today || 0}
          sub={`${stats?.new_comments_change && stats.new_comments_change >= 0 ? '+' : ''}${stats?.new_comments_change?.toFixed(1) || 0}% vs yesterday`}
          trend={stats?.new_comments_change && stats.new_comments_change >= 0 ? 'up' : 'down'}
          icon={MessageCircle}
          isLoading={statsLoading}
        />
        <StatCard
          title="Successful Matches"
          value={stats?.matches_today || 0}
          sub={`${stats?.matches_change && stats.matches_change >= 0 ? '+' : ''}${stats?.matches_change?.toFixed(1) || 0}% vs yesterday`}
          trend={stats?.matches_change && stats.matches_change >= 0 ? 'up' : 'down'}
          icon={Heart}
          isLoading={statsLoading}
        />
        <StatCard
          title="Today's DAU"
          value={stats?.dau || 0}
          sub={`${stats?.dau_change && stats.dau_change >= 0 ? '+' : ''}${stats?.dau_change?.toFixed(1) || 0}% vs yesterday`}
          trend={stats?.dau_change && stats.dau_change >= 0 ? 'up' : 'down'}
          icon={Activity}
          isLoading={statsLoading}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-7">
        <Card className="col-span-4">
          <CardHeader>
            <CardTitle>Activity & Engagement Trends</CardTitle>
            <CardDescription>7-day active users and new user data overview</CardDescription>
          </CardHeader>
          <CardContent className="pl-2">
            {chartLoading ? (
              <div className="h-[300px] flex items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <AreaChart data={chartDataFormatted}>
                  <defs>
                    <linearGradient id="colorActive" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#dc2626" stopOpacity={0.8}/>
                      <stop offset="95%" stopColor="#dc2626" stopOpacity={0}/>
                    </linearGradient>
                    <linearGradient id="colorNew" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#000000" stopOpacity={0.8}/>
                      <stop offset="95%" stopColor="#000000" stopOpacity={0}/>
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="name" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                  <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} tickFormatter={(value) => formatNumber(value)} />
                  <CartesianGrid strokeDasharray="3 3" vertical={false} />
                  <Tooltip
                    formatter={(value: number) => [value.toLocaleString(), '']}
                    labelFormatter={(label) => `Date: ${label}`}
                  />
                  <Area type="monotone" dataKey="active" name="Active Users" stroke="#dc2626" fillOpacity={1} fill="url(#colorActive)" />
                  <Area type="monotone" dataKey="new" name="New Users" stroke="#000000" fillOpacity={1} fill="url(#colorNew)" />
                </AreaChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        <Card className="col-span-3">
          <CardHeader>
            <CardTitle>System Risk Monitoring</CardTitle>
            <CardDescription>Real-time reporting and AI review status</CardDescription>
          </CardHeader>
          <CardContent>
            {alertsLoading ? (
              <div className="h-[250px] flex items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
              </div>
            ) : (
              <div className="space-y-6">
                {riskAlerts?.items?.slice(0, 2).map((alert, index) => (
                  <div key={index} className="flex items-center">
                    <div className="w-full space-y-1">
                      <div className="flex justify-between text-sm font-medium">
                        <span>{alert.title}</span>
                        <span className={getRiskColor(alert.level)}>
                          {alert.level === 'high' ? 'High' : alert.level === 'medium' ? 'Medium' : 'Low'}
                        </span>
                      </div>
                      <div className="h-2 w-full bg-slate-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full ${getRiskBarColor(alert.level)}`}
                          style={{ width: `${Math.min(alert.value, 100)}%` }}
                        ></div>
                      </div>
                      <p className="text-xs text-slate-500 pt-1">{alert.description}</p>
                    </div>
                  </div>
                ))}

                <div className="grid grid-cols-2 gap-4 pt-4">
                  <div className="bg-slate-50 p-4 rounded-lg border border-slate-100">
                    <div className="text-2xl font-bold text-slate-900">
                      {stats?.pending_reviews || 0}
                    </div>
                    <div className="text-xs text-slate-500">Pending Manual Review</div>
                  </div>
                  <div className="bg-slate-50 p-4 rounded-lg border border-slate-100">
                    <div className="text-2xl font-bold text-slate-900">
                      {stats?.banned_today || 0}
                    </div>
                    <div className="text-xs text-slate-500">Banned Today</div>
                  </div>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};
