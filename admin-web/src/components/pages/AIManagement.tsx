import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Search, Brain, Zap, AlertTriangle, CheckCircle, XCircle, Eye, TrendingUp, Activity } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

// Mock Data
const aiLogs = [
  { id: 1, userId: "U89230482", userName: "Alex Chen", action: "Content Filter", result: "Blocked", confidence: 98, reason: "Sensitive words detected", timestamp: "2024-01-05 14:23:15", category: "moderation" },
  { id: 2, userId: "U89230483", userName: "Sarah Wu", action: "Match Recommendation", result: "Success", confidence: 92, reason: "High compatibility score", timestamp: "2024-01-05 14:20:42", category: "matching" },
  { id: 3, userId: "U89230484", userName: "Mike Wang", action: "Deepsearch Query", result: "Success", confidence: 87, reason: "Profile match found", timestamp: "2024-01-05 14:15:30", category: "search" },
  { id: 4, userId: "U89230485", userName: "Lisa Li", action: "Content Filter", result: "Approved", confidence: 65, reason: "Safe content", timestamp: "2024-01-05 14:10:18", category: "moderation" },
  { id: 5, userId: "U89230486", userName: "Tom Zhang", action: "Spam Detection", result: "Flagged", confidence: 94, reason: "Repetitive messaging pattern", timestamp: "2024-01-05 14:05:55", category: "moderation" },
  { id: 6, userId: "U89230487", userName: "Emily Wang", action: "Match Recommendation", result: "Success", confidence: 89, reason: "Interest alignment", timestamp: "2024-01-05 14:00:22", category: "matching" },
  { id: 7, userId: "U89230488", userName: "David Liu", action: "Deepsearch Query", result: "No Results", confidence: 45, reason: "Criteria too specific", timestamp: "2024-01-05 13:55:10", category: "search" },
];

const performanceData = [
  { name: 'Mon', accuracy: 96, processed: 2400 },
  { name: 'Tue', accuracy: 97, processed: 2800 },
  { name: 'Wed', accuracy: 95, processed: 3200 },
  { name: 'Thu', accuracy: 98, processed: 2900 },
  { name: 'Fri', accuracy: 96, processed: 3400 },
  { name: 'Sat', accuracy: 97, processed: 3100 },
  { name: 'Sun', accuracy: 98, processed: 2700 },
];

export const AIManagement = () => {
  const ResultBadge = ({ result }: { result: string }) => {
    const styles: Record<string, { bg: string; icon: any }> = {
      Success: { bg: "bg-green-100 text-green-700 border-green-200", icon: CheckCircle },
      Blocked: { bg: "bg-red-100 text-red-700 border-red-200", icon: XCircle },
      Flagged: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", icon: AlertTriangle },
      Approved: { bg: "bg-blue-100 text-blue-700 border-blue-200", icon: CheckCircle },
      "No Results": { bg: "bg-slate-100 text-slate-600 border-slate-200", icon: XCircle },
    };
    const style = styles[result] || styles["No Results"];
    const Icon = style.icon;
    return (
      <Badge variant="outline" className={style.bg}>
        <Icon className="w-3 h-3 mr-1" />
        {result}
      </Badge>
    );
  };

  const CategoryBadge = ({ category }: { category: string }) => {
    const colors: Record<string, string> = {
      moderation: "bg-red-50 text-red-700",
      matching: "bg-purple-50 text-purple-700",
      search: "bg-blue-50 text-blue-700",
    };
    return (
      <Badge variant="secondary" className={colors[category]}>
        {category.toUpperCase()}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">AI & Deep Search Management</h2>
        <p className="text-slate-500 mt-1">Monitor AI model performance, matching algorithms, and deep search analytics</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">AI Requests Today</p>
                <p className="text-2xl font-bold">28,493</p>
                <p className="text-xs text-green-600 mt-1">+22.4% vs yesterday</p>
              </div>
              <Brain className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Model Accuracy</p>
                <p className="text-2xl font-bold">97.2%</p>
                <p className="text-xs text-green-600 mt-1">+0.8% improvement</p>
              </div>
              <TrendingUp className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Content Blocked</p>
                <p className="text-2xl font-bold">342</p>
                <p className="text-xs text-slate-500 mt-1">Automated filtering</p>
              </div>
              <XCircle className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Matches Made</p>
                <p className="text-2xl font-bold">1,847</p>
                <p className="text-xs text-slate-500 mt-1">AI recommendations</p>
              </div>
              <Zap className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Avg Response Time</p>
                <p className="text-2xl font-bold">124ms</p>
                <p className="text-xs text-green-600 mt-1">-15ms optimization</p>
              </div>
              <Activity className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Performance Chart */}
      <Card>
        <CardHeader>
          <CardTitle>AI Model Performance - 7 Day Trend</CardTitle>
          <CardDescription>Tracking accuracy rate and processing volume</CardDescription>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={280}>
            <AreaChart data={performanceData}>
              <defs>
                <linearGradient id="colorAccuracy" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#dc2626" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#dc2626" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <XAxis dataKey="name" stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
              <YAxis stroke="#888888" fontSize={12} tickLine={false} axisLine={false} />
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <Tooltip />
              <Area type="monotone" dataKey="accuracy" stroke="#dc2626" fillOpacity={1} fill="url(#colorAccuracy)" />
            </AreaChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search user / action / keywords..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Action Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Actions</SelectItem>
            <SelectItem value="filter">Content Filter</SelectItem>
            <SelectItem value="match">Match Recommendation</SelectItem>
            <SelectItem value="search">Deepsearch</SelectItem>
            <SelectItem value="spam">Spam Detection</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Result" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Results</SelectItem>
            <SelectItem value="success">Success</SelectItem>
            <SelectItem value="blocked">Blocked</SelectItem>
            <SelectItem value="flagged">Flagged</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Category" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Categories</SelectItem>
            <SelectItem value="moderation">Moderation</SelectItem>
            <SelectItem value="matching">Matching</SelectItem>
            <SelectItem value="search">Search</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Export Logs</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>AI Activity Logs ({aiLogs.length} recent records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[100px]">Log ID</TableHead>
                <TableHead>User</TableHead>
                <TableHead>AI Action</TableHead>
                <TableHead>Category</TableHead>
                <TableHead>Result</TableHead>
                <TableHead>Confidence</TableHead>
                <TableHead>Reason</TableHead>
                <TableHead>Timestamp</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {aiLogs.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{`AI${item.id.toString().padStart(6, '0')}`}</TableCell>
                  <TableCell>
                    <div>
                      <div className="font-medium text-sm">{item.userName}</div>
                      <div className="text-xs text-slate-500">{item.userId}</div>
                    </div>
                  </TableCell>
                  <TableCell className="font-medium">{item.action}</TableCell>
                  <TableCell>
                    <CategoryBadge category={item.category} />
                  </TableCell>
                  <TableCell>
                    <ResultBadge result={item.result} />
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div 
                          className={`h-full ${item.confidence >= 90 ? 'bg-green-500' : item.confidence >= 70 ? 'bg-yellow-500' : 'bg-red-500'}`}
                          style={{ width: `${item.confidence}%` }}
                        ></div>
                      </div>
                      <span className="text-sm font-medium">{item.confidence}%</span>
                    </div>
                  </TableCell>
                  <TableCell className="max-w-[200px] text-sm text-slate-600 truncate">{item.reason}</TableCell>
                  <TableCell className="text-slate-500 text-sm">{item.timestamp}</TableCell>
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
                          View Full Details
                        </DropdownMenuItem>
                        <DropdownMenuItem>
                          <Brain className="w-4 h-4 mr-2" />
                          Review AI Decision
                        </DropdownMenuItem>
                        <DropdownMenuItem>
                          <AlertTriangle className="w-4 h-4 mr-2" />
                          Report Issue
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
