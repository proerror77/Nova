import React from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Users, UserCheck, MessageCircle, Heart, Activity, AlertTriangle, TrendingUp } from "lucide-react";
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar, Legend } from 'recharts';

const dataTrend = [
  { name: 'Mon', active: 4000, comment: 2400 },
  { name: 'Tue', active: 3000, comment: 1398 },
  { name: 'Wed', active: 2000, comment: 9800 },
  { name: 'Thu', active: 2780, comment: 3908 },
  { name: 'Fri', active: 1890, comment: 4800 },
  { name: 'Sat', active: 2390, comment: 3800 },
  { name: 'Sun', active: 3490, comment: 4300 },
];

const StatCard = ({ title, value, sub, icon: Icon, trend }: any) => (
  <Card>
    <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
      <CardTitle className="text-sm font-medium text-slate-500">{title}</CardTitle>
      <Icon className="h-4 w-4 text-slate-400" />
    </CardHeader>
    <CardContent>
      <div className="text-2xl font-bold">{value}</div>
      <p className={`text-xs ${trend === 'up' ? 'text-green-500' : 'text-red-500'} flex items-center mt-1`}>
        {sub}
      </p>
    </CardContent>
  </Card>
);

export const Dashboard = () => {
  return (
    <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
      <div className="flex justify-between items-end">
        <div>
          <h2 className="text-3xl font-bold tracking-tight text-slate-900">Dashboard</h2>
          <p className="text-slate-500 mt-1">Icered Admin 实时数据监控中心</p>
        </div>
        <div className="flex space-x-2">
           <div className="bg-red-50 text-red-700 px-3 py-1 rounded text-sm font-medium border border-red-100 flex items-center">
              <AlertTriangle className="w-4 h-4 mr-2"/>
              AI 误判率上升 0.4%
           </div>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
        <StatCard title="新增注册用户" value="1,284" sub="+12.5% 较昨日" trend="up" icon={Users} />
        <StatCard title="新增认证用户" value="342" sub="+4.1% 较昨日" trend="up" icon={UserCheck} />
        <StatCard title="新增评论" value="12,394" sub="-2.4% 较昨日" trend="down" icon={MessageCircle} />
        <StatCard title="匹配成功数" value="573" sub="+8.2% 较昨日" trend="up" icon={Heart} />
        <StatCard title="今日 DAU" value="48,291" sub="+10.1% 较昨日" trend="up" icon={Activity} />
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-7">
        <Card className="col-span-4">
          <CardHeader>
            <CardTitle>活跃与互动趋势</CardTitle>
            <CardDescription>近7日活跃用户与评论交互数据概览</CardDescription>
          </CardHeader>
          <CardContent className="pl-2">
            <ResponsiveContainer width="100%" height={300}>
              <AreaChart data={dataTrend}>
                <defs>
                  <linearGradient id="colorActive" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#dc2626" stopOpacity={0.8}/>
                    <stop offset="95%" stopColor="#dc2626" stopOpacity={0}/>
                  </linearGradient>
                  <linearGradient id="colorComment" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#000000" stopOpacity={0.8}/>
                    <stop offset="95%" stopColor="#000000" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <XAxis dataKey="name" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} tickFormatter={(value) => `${value}`} />
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <Tooltip />
                <Area type="monotone" dataKey="active" stroke="#dc2626" fillOpacity={1} fill="url(#colorActive)" />
                <Area type="monotone" dataKey="comment" stroke="#000000" fillOpacity={1} fill="url(#colorComment)" />
              </AreaChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="col-span-3">
           <CardHeader>
            <CardTitle>系统风险监控</CardTitle>
            <CardDescription>实时举报与AI审核状态</CardDescription>
          </CardHeader>
          <CardContent>
             <div className="space-y-6">
                <div className="flex items-center">
                   <div className="w-full space-y-1">
                      <div className="flex justify-between text-sm font-medium">
                         <span>恶意举报量</span>
                         <span className="text-red-600">High</span>
                      </div>
                      <div className="h-2 w-full bg-slate-100 rounded-full overflow-hidden">
                         <div className="h-full bg-red-600 w-[75%]"></div>
                      </div>
                      <p className="text-xs text-slate-500 pt-1">较上周增长 15%，需重点关注社交板块</p>
                   </div>
                </div>

                <div className="flex items-center">
                   <div className="w-full space-y-1">
                      <div className="flex justify-between text-sm font-medium">
                         <span>AI 审核错误率</span>
                         <span className="text-yellow-600">Medium</span>
                      </div>
                      <div className="h-2 w-full bg-slate-100 rounded-full overflow-hidden">
                         <div className="h-full bg-yellow-500 w-[35%]"></div>
                      </div>
                      <p className="text-xs text-slate-500 pt-1">当前错误率 1.2%，处于警戒线边缘</p>
                   </div>
                </div>

                <div className="grid grid-cols-2 gap-4 pt-4">
                   <div className="bg-slate-50 p-4 rounded-lg border border-slate-100">
                      <div className="text-2xl font-bold text-slate-900">284</div>
                      <div className="text-xs text-slate-500">待人工复核</div>
                   </div>
                   <div className="bg-slate-50 p-4 rounded-lg border border-slate-100">
                      <div className="text-2xl font-bold text-slate-900">14</div>
                      <div className="text-xs text-slate-500">严重违规封禁</div>
                   </div>
                </div>
             </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
};