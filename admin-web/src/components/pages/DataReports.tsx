import React from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Button } from "../ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { BarChart3, TrendingUp, Users, Activity, DollarSign, Download, Calendar, RefreshCw } from "lucide-react";
import { BarChart, Bar, LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';

// Mock Data
const userGrowthData = [
  { month: 'Jan', newUsers: 2400, activeUsers: 18000, retention: 78 },
  { month: 'Feb', newUsers: 2800, activeUsers: 19500, retention: 82 },
  { month: 'Mar', newUsers: 3200, activeUsers: 21000, retention: 85 },
  { month: 'Apr', newUsers: 2900, activeUsers: 20500, retention: 83 },
  { month: 'May', newUsers: 3400, activeUsers: 22800, retention: 87 },
  { month: 'Jun', newUsers: 3800, activeUsers: 24500, retention: 89 },
];

const revenueData = [
  { month: 'Jan', revenue: 45000, subscriptions: 28000, inApp: 17000 },
  { month: 'Feb', revenue: 52000, subscriptions: 32000, inApp: 20000 },
  { month: 'Mar', revenue: 61000, subscriptions: 38000, inApp: 23000 },
  { month: 'Apr', revenue: 58000, subscriptions: 36000, inApp: 22000 },
  { month: 'May', revenue: 67000, subscriptions: 42000, inApp: 25000 },
  { month: 'Jun', revenue: 74000, subscriptions: 47000, inApp: 27000 },
];

const engagementData = [
  { day: 'Mon', posts: 1240, comments: 3420, likes: 8940 },
  { day: 'Tue', posts: 1380, comments: 3680, likes: 9240 },
  { day: 'Wed', posts: 1520, comments: 4120, likes: 10540 },
  { day: 'Thu', posts: 1420, comments: 3890, likes: 9780 },
  { day: 'Fri', posts: 1680, comments: 4520, likes: 11240 },
  { day: 'Sat', posts: 1920, comments: 5280, likes: 13420 },
  { day: 'Sun', posts: 1780, comments: 4920, likes: 12680 },
];

const matchingData = [
  { day: 'Mon', matches: 520, messages: 8240, unmatch: 42 },
  { day: 'Tue', matches: 580, messages: 9120, unmatch: 38 },
  { day: 'Wed', matches: 640, messages: 10240, unmatch: 45 },
  { day: 'Thu', matches: 590, messages: 9480, unmatch: 40 },
  { day: 'Fri', matches: 720, messages: 11840, unmatch: 52 },
  { day: 'Sat', matches: 840, messages: 14280, unmatch: 61 },
  { day: 'Sun', matches: 780, messages: 13240, unmatch: 58 },
];

export const DataReports = () => {
  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div className="flex justify-between items-end">
        <div>
          <h2 className="text-3xl font-bold tracking-tight text-slate-900">Data Reports Center</h2>
          <p className="text-slate-500 mt-1">Comprehensive analytics and business intelligence dashboard</p>
        </div>
        <div className="flex gap-2">
          <Select defaultValue="30days">
            <SelectTrigger className="w-[160px]">
              <SelectValue placeholder="Time Range" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="7days">Last 7 Days</SelectItem>
              <SelectItem value="30days">Last 30 Days</SelectItem>
              <SelectItem value="90days">Last 90 Days</SelectItem>
              <SelectItem value="1year">Last Year</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline">
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh Data
          </Button>
          <Button>
            <Download className="w-4 h-4 mr-2" />
            Export All Reports
          </Button>
        </div>
      </div>

      {/* Key Metrics Overview */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Total Users</p>
                <p className="text-2xl font-bold">124,589</p>
                <p className="text-xs text-green-600 mt-1">+18.2% vs last month</p>
              </div>
              <Users className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Monthly Revenue</p>
                <p className="text-2xl font-bold">$74,000</p>
                <p className="text-xs text-green-600 mt-1">+10.4% vs last month</p>
              </div>
              <DollarSign className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Daily Active Users</p>
                <p className="text-2xl font-bold">48,291</p>
                <p className="text-xs text-green-600 mt-1">38.8% of total users</p>
              </div>
              <Activity className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">User Retention</p>
                <p className="text-2xl font-bold">89%</p>
                <p className="text-xs text-green-600 mt-1">+4% improvement</p>
              </div>
              <TrendingUp className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* User Growth Analytics */}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>User Growth Trends</CardTitle>
            <CardDescription>New users vs Active users - 6 Month Overview</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={userGrowthData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="month" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip />
                <Legend />
                <Bar dataKey="newUsers" fill="#dc2626" radius={[4, 4, 0, 0]} name="New Users" />
                <Bar dataKey="activeUsers" fill="#000000" radius={[4, 4, 0, 0]} name="Active Users" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>User Retention Rate</CardTitle>
            <CardDescription>Monthly retention percentage tracking</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={userGrowthData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="month" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} domain={[70, 95]} />
                <Tooltip />
                <Line type="monotone" dataKey="retention" stroke="#dc2626" strokeWidth={3} dot={{ fill: '#dc2626', r: 5 }} name="Retention %" />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      {/* Revenue Analytics */}
      <Card>
        <CardHeader>
          <CardTitle>Revenue Performance Analysis</CardTitle>
          <CardDescription>Total revenue breakdown by subscription and in-app purchases - 6 Month Trend</CardDescription>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={320}>
            <AreaChart data={revenueData}>
              <defs>
                <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#dc2626" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#dc2626" stopOpacity={0}/>
                </linearGradient>
                <linearGradient id="colorSubs" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#000000" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#000000" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="month" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
              <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
              <Tooltip />
              <Legend />
              <Area type="monotone" dataKey="revenue" stroke="#dc2626" fillOpacity={1} fill="url(#colorRevenue)" name="Total Revenue" />
              <Area type="monotone" dataKey="subscriptions" stroke="#000000" fillOpacity={1} fill="url(#colorSubs)" name="Subscriptions" />
            </AreaChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      {/* Engagement & Matching Analytics */}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>User Engagement Metrics</CardTitle>
            <CardDescription>Daily content creation and interaction - Last 7 Days</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={engagementData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="day" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip />
                <Legend />
                <Bar dataKey="posts" fill="#dc2626" radius={[4, 4, 0, 0]} name="Posts" />
                <Bar dataKey="comments" fill="#000000" radius={[4, 4, 0, 0]} name="Comments" />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Matching & Messaging Activity</CardTitle>
            <CardDescription>Daily match creation and message volume - Last 7 Days</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={matchingData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="day" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="matches" stroke="#dc2626" strokeWidth={3} dot={{ fill: '#dc2626', r: 4 }} name="New Matches" />
                <Line type="monotone" dataKey="messages" stroke="#000000" strokeWidth={3} dot={{ fill: '#000000', r: 4 }} name="Messages Sent" />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      {/* Report Templates */}
      <Card>
        <CardHeader>
          <CardTitle>Pre-configured Report Templates</CardTitle>
          <CardDescription>Quick access to commonly used reports and exports</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-3">
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <Users className="w-5 h-5 text-blue-500" />
                <span className="font-medium">User Analytics Report</span>
              </div>
              <p className="text-xs text-slate-500 text-left">Comprehensive user data, demographics, and behavior analysis</p>
            </Button>
            
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <DollarSign className="w-5 h-5 text-green-500" />
                <span className="font-medium">Financial Performance</span>
              </div>
              <p className="text-xs text-slate-500 text-left">Revenue, transactions, and financial KPI dashboard</p>
            </Button>
            
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <Activity className="w-5 h-5 text-purple-500" />
                <span className="font-medium">Engagement Report</span>
              </div>
              <p className="text-xs text-slate-500 text-left">Content creation, interaction rates, and user activity</p>
            </Button>
            
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <TrendingUp className="w-5 h-5 text-red-500" />
                <span className="font-medium">Growth Metrics</span>
              </div>
              <p className="text-xs text-slate-500 text-left">User acquisition, retention, and growth funnel analysis</p>
            </Button>
            
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <BarChart3 className="w-5 h-5 text-yellow-500" />
                <span className="font-medium">Marketing Campaign ROI</span>
              </div>
              <p className="text-xs text-slate-500 text-left">Campaign performance and return on investment tracking</p>
            </Button>
            
            <Button variant="outline" className="h-auto py-4 flex flex-col items-start">
              <div className="flex items-center gap-2 mb-2">
                <Calendar className="w-5 h-5 text-slate-500" />
                <span className="font-medium">Custom Date Range</span>
              </div>
              <p className="text-xs text-slate-500 text-left">Generate custom reports for specific time periods</p>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
