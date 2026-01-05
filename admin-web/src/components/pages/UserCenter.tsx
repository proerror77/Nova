import React, { useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../ui/tabs";
import { Search, Eye, Ban, MoreHorizontal, ArrowLeft, ShieldAlert, MessageSquare, ThumbsUp, Activity } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";

// Mock Data
const users = [
  { id: 1, name: "Alex Chen", phone: "138****1234", status: "active", verified: true, date: "2023-10-24", avatar: "https://github.com/shadcn.png" },
  { id: 2, name: "Sarah Wu", phone: "139****5678", status: "warning", verified: true, date: "2023-10-23", avatar: "" },
  { id: 3, name: "Mike Wang", phone: "150****9012", status: "banned", verified: false, date: "2023-10-22", avatar: "" },
  { id: 4, name: "Lisa Li", phone: "186****3456", status: "active", verified: true, date: "2023-10-21", avatar: "" },
  { id: 5, name: "Tom Zhang", phone: "135****7890", status: "active", verified: false, date: "2023-10-20", avatar: "" },
];

export const UserCenter = () => {
  const [view, setView] = useState<'list' | 'detail'>('list');
  const [selectedUser, setSelectedUser] = useState<any>(null);

  const handleViewDetail = (user: any) => {
    setSelectedUser(user);
    setView('detail');
  };

  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, string> = {
      active: "bg-green-100 text-green-700 border-green-200",
      warning: "bg-yellow-100 text-yellow-700 border-yellow-200",
      banned: "bg-red-100 text-red-700 border-red-200",
    };
    return <Badge variant="outline" className={styles[status]}>{status.toUpperCase()}</Badge>;
  };

  if (view === 'detail') {
    return (
      <div className="space-y-6 animate-in slide-in-from-right-4 duration-300">
        <div className="flex items-center space-x-4">
          <Button variant="outline" size="icon" onClick={() => setView('list')}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <h2 className="text-2xl font-bold tracking-tight">用户详情档案</h2>
        </div>

        <div className="grid grid-cols-3 gap-6">
          {/* Left Column: Basic Info & Risk */}
          <div className="col-span-1 space-y-6">
            <Card>
              <CardContent className="pt-6 flex flex-col items-center text-center">
                <Avatar className="h-24 w-24 mb-4 border-4 border-slate-100">
                  <AvatarImage src={selectedUser?.avatar} />
                  <AvatarFallback>{selectedUser?.name[0]}</AvatarFallback>
                </Avatar>
                <h3 className="text-xl font-bold">{selectedUser?.name}</h3>
                <p className="text-slate-500 text-sm mb-4">ID: 89230482</p>
                <div className="flex gap-2 mb-6">
                   <StatusBadge status={selectedUser?.status} />
                   {selectedUser?.verified && <Badge variant="default" className="bg-blue-600">已认证</Badge>}
                </div>
                
                <div className="w-full grid grid-cols-2 gap-4 text-left text-sm border-t pt-4">
                  <div>
                    <span className="text-slate-500 block">手机号</span>
                    <span className="font-mono">{selectedUser?.phone}</span>
                  </div>
                  <div>
                    <span className="text-slate-500 block">注册时间</span>
                    <span>{selectedUser?.date}</span>
                  </div>
                  <div>
                    <span className="text-slate-500 block">城市</span>
                    <span>Shanghai</span>
                  </div>
                  <div>
                    <span className="text-slate-500 block">性别</span>
                    <span>Male</span>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card className="border-red-100 bg-red-50/50">
              <CardHeader className="pb-2">
                <CardTitle className="text-red-700 flex items-center">
                  <ShieldAlert className="mr-2 h-5 w-5" /> 风险记录
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-3 text-sm">
                  <div className="flex justify-between">
                    <span>被举报次数</span>
                    <span className="font-bold">3</span>
                  </div>
                  <div className="flex justify-between">
                    <span>历史封禁</span>
                    <span className="font-bold">1次 (3天)</span>
                  </div>
                  <div className="flex justify-between">
                    <span>AI 敏感词触发</span>
                    <span className="font-bold">12次</span>
                  </div>
                </div>
                <div className="mt-6 flex gap-2">
                   <Button variant="destructive" className="w-full">封禁账号</Button>
                   <Button variant="outline" className="w-full border-red-200 text-red-700 hover:bg-red-100">警告信</Button>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Right Column: Activity & Data */}
          <div className="col-span-2 space-y-6">
            <div className="grid grid-cols-3 gap-4">
               <Card>
                  <CardContent className="pt-6 flex flex-col items-center">
                     <Activity className="h-8 w-8 text-slate-400 mb-2" />
                     <span className="text-2xl font-bold">128</span>
                     <span className="text-xs text-slate-500">发布动态</span>
                  </CardContent>
               </Card>
               <Card>
                  <CardContent className="pt-6 flex flex-col items-center">
                     <MessageSquare className="h-8 w-8 text-slate-400 mb-2" />
                     <span className="text-2xl font-bold">1,024</span>
                     <span className="text-xs text-slate-500">发表评论</span>
                  </CardContent>
               </Card>
               <Card>
                  <CardContent className="pt-6 flex flex-col items-center">
                     <ThumbsUp className="h-8 w-8 text-slate-400 mb-2" />
                     <span className="text-2xl font-bold">452</span>
                     <span className="text-xs text-slate-500">获得点赞</span>
                  </CardContent>
               </Card>
            </div>

            <Card className="flex-1">
              <CardHeader>
                <CardTitle>社交匹配历史</CardTitle>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>匹配对象</TableHead>
                      <TableHead>匹配时间</TableHead>
                      <TableHead>来源</TableHead>
                      <TableHead>结果</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    <TableRow>
                       <TableCell className="flex items-center gap-2">
                          <Avatar className="h-6 w-6"><AvatarFallback>J</AvatarFallback></Avatar>
                          Jessica
                       </TableCell>
                       <TableCell>2023-10-22 14:30</TableCell>
                       <TableCell>首页推荐</TableCell>
                       <TableCell><Badge variant="secondary">已解除</Badge></TableCell>
                    </TableRow>
                    <TableRow>
                       <TableCell className="flex items-center gap-2">
                          <Avatar className="h-6 w-6"><AvatarFallback>M</AvatarFallback></Avatar>
                          Monica
                       </TableCell>
                       <TableCell>2023-10-18 09:15</TableCell>
                       <TableCell>Deepsearch</TableCell>
                       <TableCell><Badge className="bg-green-100 text-green-700 hover:bg-green-200">热聊中</Badge></TableCell>
                    </TableRow>
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    );
  }

  // Default List View
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">用户中心</h2>
        <p className="text-slate-500 mt-1">管理全平台注册用户与社交档案</p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="搜索昵称 / ID / 手机号" className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="状态" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">所有状态</SelectItem>
            <SelectItem value="active">正常</SelectItem>
            <SelectItem value="banned">已封禁</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="认证情况" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">所有</SelectItem>
            <SelectItem value="verified">已认证</SelectItem>
            <SelectItem value="unverified">未认证</SelectItem>
          </SelectContent>
        </Select>
        <Button>查询</Button>
      </div>

      {/* Table */}
      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[80px]">头像</TableHead>
              <TableHead>昵称</TableHead>
              <TableHead>手机号 (脱敏)</TableHead>
              <TableHead>状态</TableHead>
              <TableHead>认证</TableHead>
              <TableHead>注册时间</TableHead>
              <TableHead className="text-right">操作</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users.map((user) => (
              <TableRow key={user.id}>
                <TableCell>
                  <Avatar>
                    <AvatarImage src={user.avatar} />
                    <AvatarFallback>{user.name[0]}</AvatarFallback>
                  </Avatar>
                </TableCell>
                <TableCell className="font-medium">{user.name}</TableCell>
                <TableCell className="font-mono text-slate-500">{user.phone}</TableCell>
                <TableCell>
                  <StatusBadge status={user.status} />
                </TableCell>
                <TableCell>
                  {user.verified ? 
                    <Badge variant="secondary" className="bg-blue-50 text-blue-700 hover:bg-blue-100">已实名</Badge> : 
                    <span className="text-slate-400 text-sm">未认证</span>
                  }
                </TableCell>
                <TableCell className="text-slate-500">{user.date}</TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end items-center gap-2">
                     <Button variant="ghost" size="sm" onClick={() => handleViewDetail(user)}>
                        详情
                     </Button>
                     <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon">
                          <MoreHorizontal className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem>查看画像</DropdownMenuItem>
                        <DropdownMenuItem>发送站内信</DropdownMenuItem>
                        <DropdownMenuItem className="text-red-600">禁言用户</DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
};
