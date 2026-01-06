import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "../ui/card";
import { Search, Headphones, MessageCircle, AlertTriangle, CheckCircle, Clock, Star, Eye, MessageSquare } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";

// Mock Data
const tickets = [
  { id: 1, ticketId: "TK20240105001", userId: "U89230482", userName: "Alex Chen", category: "Technical Issue", subject: "Cannot upload profile photo", priority: "high", status: "open", assignee: "Support01", createdDate: "2024-01-05 14:23", rating: null },
  { id: 2, ticketId: "TK20240105002", userId: "U89230483", userName: "Sarah Wu", category: "Account Problem", subject: "Unable to verify phone number", priority: "urgent", status: "in-progress", assignee: "Support02", createdDate: "2024-01-05 13:45", rating: null },
  { id: 3, ticketId: "TK20240105003", userId: "U89230484", userName: "Mike Wang", category: "Payment Issue", subject: "Charged twice for premium upgrade", priority: "urgent", status: "in-progress", assignee: "Support03", createdDate: "2024-01-05 12:30", rating: null },
  { id: 4, ticketId: "TK20240104001", userId: "U89230485", userName: "Lisa Li", category: "Feature Request", subject: "Add dark mode to mobile app", priority: "low", status: "resolved", assignee: "Support01", createdDate: "2024-01-04 16:20", rating: 5 },
  { id: 5, ticketId: "TK20240104002", userId: "U89230486", userName: "Tom Zhang", category: "Report Abuse", subject: "Harassment from another user", priority: "urgent", status: "resolved", assignee: "Support04", createdDate: "2024-01-04 14:15", rating: 4 },
  { id: 6, ticketId: "TK20240104003", userId: "U89230487", userName: "Emily Wang", category: "General Inquiry", subject: "How to delete my account?", priority: "normal", status: "resolved", assignee: "Support02", createdDate: "2024-01-04 11:30", rating: 5 },
  { id: 7, ticketId: "TK20240103001", userId: "U89230488", userName: "David Liu", category: "Technical Issue", subject: "App crashes on iOS 17", priority: "high", status: "closed", assignee: "Support05", createdDate: "2024-01-03 10:45", rating: 3 },
];

export const FeedbackSupport = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string; icon: any }> = {
      open: { bg: "bg-blue-100 text-blue-700 border-blue-200", text: "Open", icon: MessageCircle },
      "in-progress": { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", text: "In Progress", icon: Clock },
      resolved: { bg: "bg-green-100 text-green-700 border-green-200", text: "Resolved", icon: CheckCircle },
      closed: { bg: "bg-slate-100 text-slate-600 border-slate-200", text: "Closed", icon: CheckCircle },
    };
    const style = styles[status];
    const Icon = style.icon;
    return (
      <Badge variant="outline" className={style.bg}>
        <Icon className="w-3 h-3 mr-1" />
        {style.text}
      </Badge>
    );
  };

  const PriorityBadge = ({ priority }: { priority: string }) => {
    const styles: Record<string, { bg: string; text: string }> = {
      urgent: { bg: "bg-red-100 text-red-700 border-red-300", text: "URGENT" },
      high: { bg: "bg-orange-100 text-orange-700 border-orange-200", text: "HIGH" },
      normal: { bg: "bg-blue-100 text-blue-700 border-blue-200", text: "NORMAL" },
      low: { bg: "bg-slate-100 text-slate-600 border-slate-200", text: "LOW" },
    };
    const style = styles[priority];
    return (
      <Badge variant="outline" className={style.bg}>
        {style.text}
      </Badge>
    );
  };

  const CategoryBadge = ({ category }: { category: string }) => {
    const colors: Record<string, string> = {
      "Technical Issue": "bg-purple-50 text-purple-700",
      "Account Problem": "bg-blue-50 text-blue-700",
      "Payment Issue": "bg-green-50 text-green-700",
      "Feature Request": "bg-cyan-50 text-cyan-700",
      "Report Abuse": "bg-red-50 text-red-700",
      "General Inquiry": "bg-slate-50 text-slate-700",
    };
    return (
      <Badge variant="secondary" className={colors[category] || "bg-slate-50 text-slate-700"}>
        {category}
      </Badge>
    );
  };

  const RatingDisplay = ({ rating }: { rating: number | null }) => {
    if (rating === null) return <span className="text-slate-400 text-sm">Not rated</span>;
    return (
      <div className="flex items-center gap-1">
        {[...Array(5)].map((_, i) => (
          <Star key={i} className={`w-4 h-4 ${i < rating ? 'fill-yellow-400 text-yellow-400' : 'text-slate-300'}`} />
        ))}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">User Feedback & Customer Support</h2>
        <p className="text-slate-500 mt-1">Manage support tickets, user feedback, and customer service requests</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Open Tickets</p>
                <p className="text-2xl font-bold text-blue-600">47</p>
                <p className="text-xs text-slate-500 mt-1">Awaiting response</p>
              </div>
              <MessageCircle className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">In Progress</p>
                <p className="text-2xl font-bold text-yellow-600">23</p>
                <p className="text-xs text-slate-500 mt-1">Being handled</p>
              </div>
              <Clock className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Resolved Today</p>
                <p className="text-2xl font-bold text-green-600">89</p>
                <p className="text-xs text-green-600 mt-1">+15.2% vs yesterday</p>
              </div>
              <CheckCircle className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Avg Response Time</p>
                <p className="text-2xl font-bold">2.4h</p>
                <p className="text-xs text-green-600 mt-1">-0.5h improvement</p>
              </div>
              <Headphones className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Satisfaction Rate</p>
                <p className="text-2xl font-bold">94.2%</p>
                <p className="text-xs text-slate-500 mt-1">Based on ratings</p>
              </div>
              <Star className="h-8 w-8 text-yellow-500 fill-yellow-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search ticket ID / user / subject..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Category" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Categories</SelectItem>
            <SelectItem value="technical">Technical Issue</SelectItem>
            <SelectItem value="account">Account Problem</SelectItem>
            <SelectItem value="payment">Payment Issue</SelectItem>
            <SelectItem value="feature">Feature Request</SelectItem>
            <SelectItem value="abuse">Report Abuse</SelectItem>
            <SelectItem value="inquiry">General Inquiry</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="open">Open</SelectItem>
            <SelectItem value="in-progress">In Progress</SelectItem>
            <SelectItem value="resolved">Resolved</SelectItem>
            <SelectItem value="closed">Closed</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Priority" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Priority</SelectItem>
            <SelectItem value="urgent">Urgent</SelectItem>
            <SelectItem value="high">High</SelectItem>
            <SelectItem value="normal">Normal</SelectItem>
            <SelectItem value="low">Low</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Create Ticket</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Support Tickets ({tickets.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[130px]">Ticket ID</TableHead>
                <TableHead>User</TableHead>
                <TableHead>Category</TableHead>
                <TableHead className="max-w-[250px]">Subject</TableHead>
                <TableHead>Priority</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Assignee</TableHead>
                <TableHead>Created Time</TableHead>
                <TableHead>Rating</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {tickets.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{item.ticketId}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-8 w-8">
                        <AvatarFallback>{item.userName[0]}</AvatarFallback>
                      </Avatar>
                      <div>
                        <div className="font-medium text-sm">{item.userName}</div>
                        <div className="text-xs text-slate-500">{item.userId}</div>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <CategoryBadge category={item.category} />
                  </TableCell>
                  <TableCell className="max-w-[250px]">
                    <p className="text-sm truncate">{item.subject}</p>
                  </TableCell>
                  <TableCell>
                    <PriorityBadge priority={item.priority} />
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline" className="bg-purple-50 text-purple-700">
                      <Headphones className="w-3 h-3 mr-1" />
                      {item.assignee}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-slate-500 text-sm">{item.createdDate}</TableCell>
                  <TableCell>
                    <RatingDisplay rating={item.rating} />
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
                          View Details
                        </DropdownMenuItem>
                        <DropdownMenuItem>
                          <MessageSquare className="w-4 h-4 mr-2" />
                          Reply to Ticket
                        </DropdownMenuItem>
                        {item.status === 'open' && (
                          <DropdownMenuItem className="text-blue-600">
                            Assign to Me
                          </DropdownMenuItem>
                        )}
                        {(item.status === 'open' || item.status === 'in-progress') && (
                          <DropdownMenuItem className="text-green-600">
                            <CheckCircle className="w-4 h-4 mr-2" />
                            Mark as Resolved
                          </DropdownMenuItem>
                        )}
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
