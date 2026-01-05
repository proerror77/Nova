import React, { useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../ui/tabs";
import {
  Search, Eye, Trash2, CheckCircle, XCircle, AlertTriangle,
  MessageSquare, Image, Video, Flag, Clock, MoreHorizontal,
  ArrowLeft, ThumbsUp, Share2
} from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../ui/dialog";

// Mock Data - 帖子
const mockPosts = [
  {
    id: 1,
    author: "Alex Chen",
    avatar: "https://github.com/shadcn.png",
    content: "今天天气真好，出去走走 #生活 #日常",
    mediaType: "image",
    mediaCount: 3,
    status: "pending",
    reportCount: 2,
    likes: 128,
    comments: 24,
    createdAt: "2024-01-05 14:30",
    reportReason: "疑似广告内容"
  },
  {
    id: 2,
    author: "Sarah Wu",
    avatar: "",
    content: "分享一个超棒的餐厅发现！环境很好，推荐给大家",
    mediaType: "image",
    mediaCount: 5,
    status: "approved",
    reportCount: 0,
    likes: 342,
    comments: 56,
    createdAt: "2024-01-05 12:15",
    reportReason: null
  },
  {
    id: 3,
    author: "Mike Wang",
    avatar: "",
    content: "这个视频太搞笑了哈哈哈",
    mediaType: "video",
    mediaCount: 1,
    status: "rejected",
    reportCount: 5,
    likes: 89,
    comments: 12,
    createdAt: "2024-01-05 10:00",
    reportReason: "违规内容：涉及低俗"
  },
  {
    id: 4,
    author: "Lisa Li",
    avatar: "",
    content: "周末去爬山，风景太美了！强烈推荐这条路线",
    mediaType: "image",
    mediaCount: 8,
    status: "pending",
    reportCount: 1,
    likes: 567,
    comments: 89,
    createdAt: "2024-01-04 18:45",
    reportReason: "图片涉嫌抄袭"
  },
];

// Mock Data - 评论
const mockComments = [
  {
    id: 1,
    author: "Tom Zhang",
    avatar: "",
    content: "这个真的太棒了！必须支持一下",
    postId: 1,
    postPreview: "今天天气真好，出去走走...",
    status: "pending",
    reportCount: 1,
    createdAt: "2024-01-05 15:30",
    reportReason: "无意义灌水"
  },
  {
    id: 2,
    author: "Jenny Liu",
    avatar: "",
    content: "私信我有优惠哦，加V：xxx123",
    postId: 2,
    postPreview: "分享一个超棒的餐厅发现...",
    status: "pending",
    reportCount: 3,
    createdAt: "2024-01-05 14:20",
    reportReason: "疑似广告/引流"
  },
  {
    id: 3,
    author: "David Chen",
    avatar: "",
    content: "博主拍照技术真好，学习了",
    postId: 4,
    postPreview: "周末去爬山，风景太美了...",
    status: "approved",
    reportCount: 0,
    createdAt: "2024-01-05 13:10",
    reportReason: null
  },
];

export const ContentManage = () => {
  const [activeTab, setActiveTab] = useState('posts');
  const [statusFilter, setStatusFilter] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedItem, setSelectedItem] = useState<any>(null);
  const [actionDialog, setActionDialog] = useState<{open: boolean, type: 'approve' | 'reject' | null, item: any}>({
    open: false,
    type: null,
    item: null
  });

  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, string> = {
      pending: "bg-yellow-100 text-yellow-700 border-yellow-200",
      approved: "bg-green-100 text-green-700 border-green-200",
      rejected: "bg-red-100 text-red-700 border-red-200",
    };
    const labels: Record<string, string> = {
      pending: "待审核",
      approved: "已通过",
      rejected: "已拒绝",
    };
    return <Badge variant="outline" className={styles[status]}>{labels[status]}</Badge>;
  };

  const MediaTypeBadge = ({ type, count }: { type: string, count: number }) => {
    const Icon = type === 'video' ? Video : Image;
    return (
      <div className="flex items-center text-slate-500 text-sm">
        <Icon className="h-4 w-4 mr-1" />
        {count}
      </div>
    );
  };

  const handleAction = (type: 'approve' | 'reject', item: any) => {
    setActionDialog({ open: true, type, item });
  };

  const confirmAction = () => {
    // Mock action - 实际会调用 API
    console.log(`${actionDialog.type} item:`, actionDialog.item);
    setActionDialog({ open: false, type: null, item: null });
  };

  const filteredPosts = mockPosts.filter(post =>
    (statusFilter === 'all' || post.status === statusFilter) &&
    (searchQuery === '' || post.content.includes(searchQuery) || post.author.includes(searchQuery))
  );

  const filteredComments = mockComments.filter(comment =>
    (statusFilter === 'all' || comment.status === statusFilter) &&
    (searchQuery === '' || comment.content.includes(searchQuery) || comment.author.includes(searchQuery))
  );

  const pendingCount = {
    posts: mockPosts.filter(p => p.status === 'pending').length,
    comments: mockComments.filter(c => c.status === 'pending').length,
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">内容 & 评论</h2>
        <p className="text-slate-500 mt-1">管理平台所有内容发布、评论审核与违规处理</p>
      </div>

      {/* 统计卡片 */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">待审核帖子</p>
                <p className="text-2xl font-bold text-yellow-600">{pendingCount.posts}</p>
              </div>
              <Clock className="h-8 w-8 text-yellow-500 opacity-50" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">待审核评论</p>
                <p className="text-2xl font-bold text-yellow-600">{pendingCount.comments}</p>
              </div>
              <MessageSquare className="h-8 w-8 text-yellow-500 opacity-50" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">今日已处理</p>
                <p className="text-2xl font-bold text-green-600">156</p>
              </div>
              <CheckCircle className="h-8 w-8 text-green-500 opacity-50" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">举报待处理</p>
                <p className="text-2xl font-bold text-red-600">23</p>
              </div>
              <Flag className="h-8 w-8 text-red-500 opacity-50" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="posts" className="relative">
            帖子管理
            {pendingCount.posts > 0 && (
              <span className="ml-2 bg-yellow-500 text-white text-xs px-1.5 py-0.5 rounded-full">
                {pendingCount.posts}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="comments" className="relative">
            评论管理
            {pendingCount.comments > 0 && (
              <span className="ml-2 bg-yellow-500 text-white text-xs px-1.5 py-0.5 rounded-full">
                {pendingCount.comments}
              </span>
            )}
          </TabsTrigger>
        </TabsList>

        {/* 筛选器 */}
        <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm mt-4">
          <div className="flex-1 min-w-[200px]">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
              <Input
                placeholder="搜索内容 / 用户..."
                className="pl-9"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
          </div>
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-[160px]">
              <SelectValue placeholder="状态" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">所有状态</SelectItem>
              <SelectItem value="pending">待审核</SelectItem>
              <SelectItem value="approved">已通过</SelectItem>
              <SelectItem value="rejected">已拒绝</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline">
            <Flag className="h-4 w-4 mr-2" />
            只看举报
          </Button>
        </div>

        {/* 帖子列表 */}
        <TabsContent value="posts" className="mt-0">
          <Card>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[300px]">内容</TableHead>
                  <TableHead>作者</TableHead>
                  <TableHead>媒体</TableHead>
                  <TableHead>互动</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead>举报</TableHead>
                  <TableHead>时间</TableHead>
                  <TableHead className="text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredPosts.map((post) => (
                  <TableRow key={post.id}>
                    <TableCell>
                      <p className="line-clamp-2 text-sm">{post.content}</p>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Avatar className="h-6 w-6">
                          <AvatarImage src={post.avatar} />
                          <AvatarFallback>{post.author[0]}</AvatarFallback>
                        </Avatar>
                        <span className="text-sm">{post.author}</span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <MediaTypeBadge type={post.mediaType} count={post.mediaCount} />
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-3 text-sm text-slate-500">
                        <span className="flex items-center"><ThumbsUp className="h-3 w-3 mr-1" />{post.likes}</span>
                        <span className="flex items-center"><MessageSquare className="h-3 w-3 mr-1" />{post.comments}</span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={post.status} />
                    </TableCell>
                    <TableCell>
                      {post.reportCount > 0 ? (
                        <Badge variant="destructive" className="bg-red-100 text-red-700 hover:bg-red-100">
                          <Flag className="h-3 w-3 mr-1" />
                          {post.reportCount}
                        </Badge>
                      ) : (
                        <span className="text-slate-400 text-sm">-</span>
                      )}
                    </TableCell>
                    <TableCell className="text-slate-500 text-sm">{post.createdAt}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end items-center gap-1">
                        {post.status === 'pending' && (
                          <>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700 hover:bg-green-50"
                              onClick={() => handleAction('approve', post)}
                            >
                              <CheckCircle className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                              onClick={() => handleAction('reject', post)}
                            >
                              <XCircle className="h-4 w-4" />
                            </Button>
                          </>
                        )}
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon">
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem>
                              <Eye className="h-4 w-4 mr-2" />
                              查看详情
                            </DropdownMenuItem>
                            <DropdownMenuItem>查看作者</DropdownMenuItem>
                            <DropdownMenuItem className="text-red-600">
                              <Trash2 className="h-4 w-4 mr-2" />
                              删除帖子
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        </TabsContent>

        {/* 评论列表 */}
        <TabsContent value="comments" className="mt-0">
          <Card>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[250px]">评论内容</TableHead>
                  <TableHead>评论者</TableHead>
                  <TableHead className="w-[200px]">原帖预览</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead>举报</TableHead>
                  <TableHead>时间</TableHead>
                  <TableHead className="text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredComments.map((comment) => (
                  <TableRow key={comment.id}>
                    <TableCell>
                      <p className="line-clamp-2 text-sm">{comment.content}</p>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Avatar className="h-6 w-6">
                          <AvatarFallback>{comment.author[0]}</AvatarFallback>
                        </Avatar>
                        <span className="text-sm">{comment.author}</span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <p className="line-clamp-1 text-xs text-slate-500">{comment.postPreview}</p>
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={comment.status} />
                    </TableCell>
                    <TableCell>
                      {comment.reportCount > 0 ? (
                        <Badge variant="destructive" className="bg-red-100 text-red-700 hover:bg-red-100">
                          <Flag className="h-3 w-3 mr-1" />
                          {comment.reportCount}
                        </Badge>
                      ) : (
                        <span className="text-slate-400 text-sm">-</span>
                      )}
                    </TableCell>
                    <TableCell className="text-slate-500 text-sm">{comment.createdAt}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end items-center gap-1">
                        {comment.status === 'pending' && (
                          <>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-green-600 hover:text-green-700 hover:bg-green-50"
                              onClick={() => handleAction('approve', comment)}
                            >
                              <CheckCircle className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                              onClick={() => handleAction('reject', comment)}
                            >
                              <XCircle className="h-4 w-4" />
                            </Button>
                          </>
                        )}
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon">
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem>查看原帖</DropdownMenuItem>
                            <DropdownMenuItem>查看评论者</DropdownMenuItem>
                            <DropdownMenuItem className="text-red-600">
                              <Trash2 className="h-4 w-4 mr-2" />
                              删除评论
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        </TabsContent>
      </Tabs>

      {/* 确认对话框 */}
      <Dialog open={actionDialog.open} onOpenChange={(open) => setActionDialog({...actionDialog, open})}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {actionDialog.type === 'approve' ? '确认通过' : '确认拒绝'}
            </DialogTitle>
            <DialogDescription>
              {actionDialog.type === 'approve'
                ? '确定要通过这条内容吗？通过后将正常展示给用户。'
                : '确定要拒绝这条内容吗？拒绝后内容将被下架。'
              }
            </DialogDescription>
          </DialogHeader>
          {actionDialog.item?.reportReason && (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3 text-sm">
              <div className="flex items-center text-yellow-700 font-medium mb-1">
                <AlertTriangle className="h-4 w-4 mr-2" />
                举报原因
              </div>
              <p className="text-yellow-600">{actionDialog.item.reportReason}</p>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setActionDialog({open: false, type: null, item: null})}>
              取消
            </Button>
            <Button
              variant={actionDialog.type === 'approve' ? 'default' : 'destructive'}
              onClick={confirmAction}
            >
              确认{actionDialog.type === 'approve' ? '通过' : '拒绝'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
