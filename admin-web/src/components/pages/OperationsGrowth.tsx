import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Search, TrendingUp, Users, Target, Megaphone, Mail, Gift, Eye, Edit, Trash2 } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts';

// Mock Data
const campaigns = [
  { id: 1, name: "New Year Welcome Bonus", type: "promotion", status: "active", startDate: "2024-01-01", endDate: "2024-01-31", target: "New Users", reach: 12845, conversions: 3421, budget: "$5,000", roi: "234%" },
  { id: 2, name: "Premium Upgrade Campaign", type: "email", status: "active", startDate: "2024-01-03", endDate: "2024-01-15", target: "Free Users", reach: 28394, conversions: 892, budget: "$2,500", roi: "156%" },
  { id: 3, name: "Referral Rewards Program", type: "referral", status: "completed", startDate: "2023-12-15", endDate: "2024-01-05", target: "All Users", reach: 45231, conversions: 5673, budget: "$8,000", roi: "312%" },
  { id: 4, name: "Valentine's Day Special", type: "promotion", status: "scheduled", startDate: "2024-02-10", endDate: "2024-02-14", target: "Active Matches", reach: 0, conversions: 0, budget: "$6,000", roi: "-" },
  { id: 5, name: "Push Notification Test", type: "push", status: "active", startDate: "2024-01-04", endDate: "2024-01-10", target: "Inactive Users", reach: 8492, conversions: 234, budget: "$500", roi: "89%" },
  { id: 6, name: "Weekend Engagement Boost", type: "promotion", status: "completed", startDate: "2023-12-23", endDate: "2023-12-24", target: "All Users", reach: 52394, conversions: 8934, budget: "$3,000", roi: "428%" },
  { id: 7, name: "Content Creator Program", type: "partnership", status: "active", startDate: "2024-01-01", endDate: "2024-03-31", target: "Verified Users", reach: 3421, conversions: 892, budget: "$15,000", roi: "178%" },
];

const growthData = [
  { name: 'Week 1', newUsers: 2400, activeUsers: 4200, retention: 78 },
  { name: 'Week 2', newUsers: 2800, activeUsers: 4800, retention: 82 },
  { name: 'Week 3', newUsers: 3200, activeUsers: 5400, retention: 85 },
  { name: 'Week 4', newUsers: 2900, activeUsers: 5100, retention: 83 },
];

export const OperationsGrowth = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string }> = {
      active: { bg: "bg-green-100 text-green-700 border-green-200", text: "Active" },
      completed: { bg: "bg-slate-100 text-slate-600 border-slate-200", text: "Completed" },
      scheduled: { bg: "bg-blue-100 text-blue-700 border-blue-200", text: "Scheduled" },
      paused: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", text: "Paused" },
    };
    const style = styles[status];
    return <Badge variant="outline" className={style.bg}>{style.text}</Badge>;
  };

  const TypeBadge = ({ type }: { type: string }) => {
    const colors: Record<string, string> = {
      promotion: "bg-red-50 text-red-700",
      email: "bg-purple-50 text-purple-700",
      referral: "bg-green-50 text-green-700",
      push: "bg-blue-50 text-blue-700",
      partnership: "bg-yellow-50 text-yellow-700",
    };
    return (
      <Badge variant="secondary" className={colors[type]}>
        {type.toUpperCase()}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">Operations & Growth Management</h2>
        <p className="text-slate-500 mt-1">Manage marketing campaigns, user acquisition, and growth strategies</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Active Campaigns</p>
                <p className="text-2xl font-bold">12</p>
                <p className="text-xs text-slate-500 mt-1">Running now</p>
              </div>
              <Megaphone className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Total Reach (30d)</p>
                <p className="text-2xl font-bold">284K</p>
                <p className="text-xs text-green-600 mt-1">+34.5% vs last month</p>
              </div>
              <Users className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Conversion Rate</p>
                <p className="text-2xl font-bold">18.4%</p>
                <p className="text-xs text-green-600 mt-1">+2.3% improvement</p>
              </div>
              <Target className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Avg ROI</p>
                <p className="text-2xl font-bold">245%</p>
                <p className="text-xs text-slate-500 mt-1">Across all campaigns</p>
              </div>
              <TrendingUp className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Monthly Budget</p>
                <p className="text-2xl font-bold">$42K</p>
                <p className="text-xs text-slate-500 mt-1">$18K remaining</p>
              </div>
              <Gift className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Growth Charts */}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>User Acquisition Trend</CardTitle>
            <CardDescription>New vs Active Users - Last 4 Weeks</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={growthData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="name" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip />
                <Bar dataKey="newUsers" fill="#dc2626" radius={[4, 4, 0, 0]} />
                <Bar dataKey="activeUsers" fill="#000000" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Retention Rate Trend</CardTitle>
            <CardDescription>User retention percentage over time</CardDescription>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={growthData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="name" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
                <Tooltip />
                <Line type="monotone" dataKey="retention" stroke="#dc2626" strokeWidth={3} dot={{ fill: '#dc2626', r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search campaign name..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Campaign Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            <SelectItem value="promotion">Promotion</SelectItem>
            <SelectItem value="email">Email Campaign</SelectItem>
            <SelectItem value="referral">Referral</SelectItem>
            <SelectItem value="push">Push Notification</SelectItem>
            <SelectItem value="partnership">Partnership</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="scheduled">Scheduled</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Create Campaign</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Marketing Campaigns ({campaigns.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[100px]">Campaign ID</TableHead>
                <TableHead>Campaign Name</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Target Audience</TableHead>
                <TableHead>Reach</TableHead>
                <TableHead>Conversions</TableHead>
                <TableHead>Budget</TableHead>
                <TableHead>ROI</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {campaigns.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{`CP${item.id.toString().padStart(6, '0')}`}</TableCell>
                  <TableCell>
                    <div>
                      <div className="font-medium">{item.name}</div>
                      <div className="text-xs text-slate-500">{item.startDate} - {item.endDate}</div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <TypeBadge type={item.type} />
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="bg-blue-50 text-blue-700">
                      <Target className="w-3 h-3 mr-1" />
                      {item.target}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-medium">{item.reach.toLocaleString()}</TableCell>
                  <TableCell className="font-medium text-green-600">{item.conversions.toLocaleString()}</TableCell>
                  <TableCell className="font-medium">{item.budget}</TableCell>
                  <TableCell>
                    <span className={item.roi !== '-' ? 'text-green-600 font-bold' : 'text-slate-400'}>
                      {item.roi}
                    </span>
                  </TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="sm">
                          Actions
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem>
                          <Eye className="w-4 h-4 mr-2" />
                          View Analytics
                        </DropdownMenuItem>
                        <DropdownMenuItem>
                          <Edit className="w-4 h-4 mr-2" />
                          Edit Campaign
                        </DropdownMenuItem>
                        {item.status === 'active' && (
                          <DropdownMenuItem className="text-yellow-600">
                            Pause Campaign
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem className="text-red-600">
                          <Trash2 className="w-4 h-4 mr-2" />
                          Delete Campaign
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
};
