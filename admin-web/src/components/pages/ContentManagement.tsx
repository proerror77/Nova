import React, { useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "../ui/card";
import { Search, Eye, Trash2, AlertTriangle, CheckCircle, XCircle, MessageSquare, Image as ImageIcon, Loader2 } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { usePosts, useComments, useApprovePost, useRejectPost, useApproveComment, useRejectComment } from '../../hooks';

export const ContentManagement = () => {
  const [contentType, setContentType] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [actionDialog, setActionDialog] = useState<{
    open: boolean;
    type: 'approve' | 'reject' | null;
    item: any;
    contentType: 'post' | 'comment';
  }>({ open: false, type: null, item: null, contentType: 'post' });

  // API Hooks
  const { data: postsData, isLoading: postsLoading, error: postsError } = usePosts({
    status: statusFilter !== 'all' ? statusFilter : undefined,
  });
  const { data: commentsData, isLoading: commentsLoading, error: commentsError } = useComments({
    status: statusFilter !== 'all' ? statusFilter : undefined,
  });

  // Mutations
  const approvePost = useApprovePost();
  const rejectPost = useRejectPost();
  const approveComment = useApproveComment();
  const rejectComment = useRejectComment();

  const isLoading = postsLoading || commentsLoading;
  const hasError = postsError || commentsError;

  // Combine and filter data
  const posts = postsData?.posts || [];
  const comments = commentsData?.comments || [];

  const combinedContent = [
    ...posts.map((post: any) => ({
      id: post.id,
      odId: post.id,
      userId: post.user_id,
      userName: post.author_name || 'Unknown',
      type: 'post' as const,
      content: post.content || post.caption || '',
      status: post.status,
      reports: post.report_count || 0,
      likes: post.likes_count || 0,
      comments: post.comments_count || 0,
      date: new Date(post.created_at).toLocaleString(),
      hasMedia: post.media_count > 0 || post.has_media,
    })),
    ...comments.map((comment: any) => ({
      id: `comment-${comment.id}`,
      odId: comment.id,
      userId: comment.user_id,
      userName: comment.author_name || 'Unknown',
      type: 'comment' as const,
      content: comment.content || '',
      status: comment.status,
      reports: comment.report_count || 0,
      likes: comment.likes_count || 0,
      comments: 0,
      date: new Date(comment.created_at).toLocaleString(),
      hasMedia: false,
    })),
  ].filter(item => {
    if (contentType !== 'all' && item.type !== contentType) return false;
    if (searchQuery && !item.content.toLowerCase().includes(searchQuery.toLowerCase()) &&
        !item.userName.toLowerCase().includes(searchQuery.toLowerCase())) return false;
    return true;
  });

  // Stats
  const pendingCount = combinedContent.filter(c => c.status === 'pending').length;
  const flaggedCount = combinedContent.filter(c => c.status === 'flagged' || c.reports > 0).length;

  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string; icon: any }> = {
      approved: { bg: "bg-green-100 text-green-700 border-green-200", text: "Approved", icon: CheckCircle },
      published: { bg: "bg-green-100 text-green-700 border-green-200", text: "Published", icon: CheckCircle },
      pending: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", text: "Pending Review", icon: AlertTriangle },
      flagged: { bg: "bg-orange-100 text-orange-700 border-orange-200", text: "Flagged", icon: AlertTriangle },
      removed: { bg: "bg-red-100 text-red-700 border-red-200", text: "Removed", icon: XCircle },
      rejected: { bg: "bg-red-100 text-red-700 border-red-200", text: "Rejected", icon: XCircle },
    };
    const style = styles[status] || styles.pending;
    const Icon = style.icon;
    return (
      <Badge variant="outline" className={style.bg}>
        <Icon className="w-3 h-3 mr-1" />
        {style.text}
      </Badge>
    );
  };

  const handleAction = (type: 'approve' | 'reject', item: any, contentType: 'post' | 'comment') => {
    setActionDialog({ open: true, type, item, contentType });
  };

  const confirmAction = () => {
    const { type, item, contentType } = actionDialog;
    if (!type || !item) return;

    if (type === 'approve') {
      if (contentType === 'post') {
        approvePost.mutate({ id: item.odId });
      } else {
        approveComment.mutate({ id: item.odId });
      }
    } else {
      if (contentType === 'post') {
        rejectPost.mutate({ id: item.odId, data: { reason: 'Rejected by admin' } });
      } else {
        rejectComment.mutate({ id: item.odId, data: { reason: 'Rejected by admin' } });
      }
    }
    setActionDialog({ open: false, type: null, item: null, contentType: 'post' });
  };

  const isMutating = approvePost.isPending || rejectPost.isPending ||
                     approveComment.isPending || rejectComment.isPending;

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">Content & Comment Management</h2>
        <p className="text-slate-500 mt-1">Monitor and moderate all user-generated content and comments</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Total Posts</p>
                <p className="text-2xl font-bold">{posts.length}</p>
                <p className="text-xs text-slate-500 mt-1">From API</p>
              </div>
              <MessageSquare className="h-8 w-8 text-slate-400" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Pending Review</p>
                <p className="text-2xl font-bold text-yellow-600">{pendingCount}</p>
                <p className="text-xs text-slate-500 mt-1">Requires attention</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Flagged Content</p>
                <p className="text-2xl font-bold text-red-600">{flaggedCount}</p>
                <p className="text-xs text-red-600 mt-1">High priority</p>
              </div>
              <XCircle className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Total Comments</p>
                <p className="text-2xl font-bold">{comments.length}</p>
                <p className="text-xs text-slate-500 mt-1">From API</p>
              </div>
              <CheckCircle className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input
              placeholder="Search content / user / ID..."
              className="pl-9"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
        </div>
        <Select value={contentType} onValueChange={setContentType}>
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Content Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            <SelectItem value="post">Posts</SelectItem>
            <SelectItem value="comment">Comments</SelectItem>
          </SelectContent>
        </Select>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="approved">Approved</SelectItem>
            <SelectItem value="rejected">Rejected</SelectItem>
            <SelectItem value="removed">Removed</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="outline">Export Data</Button>
      </div>

      {/* Error State */}
      {hasError && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          Unable to load content data. Please try again later.
        </div>
      )}

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Content List ({combinedContent.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
              <span className="ml-2 text-slate-500">Loading content...</span>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[100px]">Content ID</TableHead>
                  <TableHead>User</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="max-w-[300px]">Content Preview</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Reports</TableHead>
                  <TableHead>Engagement</TableHead>
                  <TableHead>Created Time</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {combinedContent.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={9} className="text-center py-8 text-slate-500">
                      No content found
                    </TableCell>
                  </TableRow>
                ) : (
                  combinedContent.map((item) => (
                    <TableRow key={item.id}>
                      <TableCell className="font-mono text-sm">
                        {item.type === 'post' ? `P${String(item.odId).slice(-6)}` : `C${String(item.odId).slice(-6)}`}
                      </TableCell>
                      <TableCell>
                        <div>
                          <div className="font-medium">{item.userName}</div>
                          <div className="text-xs text-slate-500">{item.userId}</div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="secondary" className={item.type === 'post' ? 'bg-blue-50 text-blue-700' : 'bg-purple-50 text-purple-700'}>
                          <MessageSquare className="w-3 h-3 mr-1" />
                          {item.type.toUpperCase()}
                        </Badge>
                      </TableCell>
                      <TableCell className="max-w-[300px]">
                        <div className="flex items-start gap-2">
                          <p className="text-sm truncate">{item.content}</p>
                          {item.hasMedia && <ImageIcon className="w-4 h-4 text-slate-400 flex-shrink-0" />}
                        </div>
                      </TableCell>
                      <TableCell>
                        <StatusBadge status={item.status} />
                      </TableCell>
                      <TableCell>
                        <span className={item.reports > 0 ? 'text-red-600 font-bold' : 'text-slate-500'}>
                          {item.reports}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="text-xs text-slate-500">
                          <div>❤️ {item.likes}</div>
                          <div>💬 {item.comments}</div>
                        </div>
                      </TableCell>
                      <TableCell className="text-slate-500 text-sm">{item.date}</TableCell>
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
                              View Full Content
                            </DropdownMenuItem>
                            {item.status === 'pending' && (
                              <>
                                <DropdownMenuItem
                                  className="text-green-600"
                                  onClick={() => handleAction('approve', item, item.type)}
                                >
                                  <CheckCircle className="w-4 h-4 mr-2" />
                                  Approve
                                </DropdownMenuItem>
                                <DropdownMenuItem
                                  className="text-red-600"
                                  onClick={() => handleAction('reject', item, item.type)}
                                >
                                  <XCircle className="w-4 h-4 mr-2" />
                                  Reject
                                </DropdownMenuItem>
                              </>
                            )}
                            <DropdownMenuItem className="text-red-600">
                              <Trash2 className="w-4 h-4 mr-2" />
                              Remove Content
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Confirmation Dialog */}
      <Dialog open={actionDialog.open} onOpenChange={(open) => setActionDialog({ ...actionDialog, open })}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {actionDialog.type === 'approve' ? 'Confirm Approval' : 'Confirm Rejection'}
            </DialogTitle>
            <DialogDescription>
              {actionDialog.type === 'approve'
                ? 'Are you sure you want to approve this content? It will be visible to users.'
                : 'Are you sure you want to reject this content? It will be removed from display.'
              }
            </DialogDescription>
          </DialogHeader>
          {actionDialog.item?.reports > 0 && (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3 text-sm">
              <div className="flex items-center text-yellow-700 font-medium mb-1">
                <AlertTriangle className="h-4 w-4 mr-2" />
                Report Notice
              </div>
              <p className="text-yellow-600">This content has {actionDialog.item.reports} report(s)</p>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setActionDialog({ open: false, type: null, item: null, contentType: 'post' })}>
              Cancel
            </Button>
            <Button
              variant={actionDialog.type === 'approve' ? 'default' : 'destructive'}
              onClick={confirmAction}
              disabled={isMutating}
            >
              {isMutating && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Confirm {actionDialog.type === 'approve' ? 'Approval' : 'Rejection'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
