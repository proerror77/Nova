import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "../ui/card";
import { Search, Shield, User, Edit, Trash2, Eye, AlertTriangle, CheckCircle, Settings, Lock } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";

// Mock Data - Admin Users
const adminUsers = [
  { id: 1, adminId: "A001", name: "Admin Zhang", email: "zhang@icered.com", role: "Super Admin", status: "active", lastLogin: "2024-01-05 14:23", permissions: ["All Access"] },
  { id: 2, adminId: "A002", name: "Support Li", email: "li@icered.com", role: "Support Manager", status: "active", lastLogin: "2024-01-05 13:45", permissions: ["User Management", "Support"] },
  { id: 3, adminId: "A003", name: "Finance Wang", email: "wang@icered.com", role: "Finance Admin", status: "active", lastLogin: "2024-01-05 12:30", permissions: ["Payment", "Reports"] },
  { id: 4, adminId: "A004", name: "Content Chen", email: "chen@icered.com", role: "Content Moderator", status: "active", lastLogin: "2024-01-05 11:15", permissions: ["Content Management"] },
  { id: 5, adminId: "A005", name: "Former Admin", email: "former@icered.com", role: "Former Admin", status: "disabled", lastLogin: "2024-01-01 09:00", permissions: ["None"] },
];

// Mock Data - Operation Logs
const operationLogs = [
  { id: 1, logId: "LOG20240105001", adminId: "A001", adminName: "Admin Zhang", action: "User Ban", target: "User U89230484 (Mike Wang)", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 14:23:15", details: "Banned for policy violation" },
  { id: 2, logId: "LOG20240105002", adminId: "A002", adminName: "Support Li", action: "Content Removal", target: "Post C000342", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 13:45:22", details: "Removed inappropriate content" },
  { id: 3, logId: "LOG20240105003", adminId: "A003", adminName: "Finance Wang", action: "Refund Process", target: "Order ORD20240105003", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 12:30:45", details: "Customer refund request approved" },
  { id: 4, logId: "LOG20240105004", adminId: "A001", adminName: "Admin Zhang", action: "Permission Update", target: "Admin A004", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 11:15:33", details: "Updated content moderation permissions" },
  { id: 5, logId: "LOG20240105005", adminId: "A004", adminName: "Content Chen", action: "Post Approval", target: "Post C000456", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 10:20:18", details: "Approved flagged content after review" },
  { id: 6, logId: "LOG20240105006", adminId: "A002", adminName: "Support Li", action: "Ticket Resolution", target: "Ticket TK20240105001", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 09:45:55", details: "Resolved user technical issue" },
  { id: 7, logId: "LOG20240105007", adminId: "A001", adminName: "Admin Zhang", action: "System Settings", target: "AI Filter Threshold", result: "Success", ip: "192.168.1.***", timestamp: "2024-01-05 09:12:40", details: "Updated sensitivity from 85% to 90%" },
];

export const SystemLogs = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string }> = {
      active: { bg: "bg-green-100 text-green-700 border-green-200", text: "Active" },
      disabled: { bg: "bg-red-100 text-red-700 border-red-200", text: "Disabled" },
      suspended: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", text: "Suspended" },
    };
    const style = styles[status];
    return <Badge variant="outline" className={style.bg}>{style.text}</Badge>;
  };

  const RoleBadge = ({ role }: { role: string }) => {
    const colors: Record<string, string> = {
      "Super Admin": "bg-red-50 text-red-700 border-red-200",
      "Support Manager": "bg-blue-50 text-blue-700 border-blue-200",
      "Finance Admin": "bg-green-50 text-green-700 border-green-200",
      "Content Moderator": "bg-purple-50 text-purple-700 border-purple-200",
      "Former Admin": "bg-slate-50 text-slate-500 border-slate-200",
    };
    return (
      <Badge variant="outline" className={colors[role] || "bg-slate-50 text-slate-700"}>
        <Shield className="w-3 h-3 mr-1" />
        {role}
      </Badge>
    );
  };

  const ActionBadge = ({ action }: { action: string }) => {
    const config: Record<string, { color: string; icon: any }> = {
      "User Ban": { color: "bg-red-50 text-red-700", icon: AlertTriangle },
      "Content Removal": { color: "bg-orange-50 text-orange-700", icon: Trash2 },
      "Refund Process": { color: "bg-green-50 text-green-700", icon: CheckCircle },
      "Permission Update": { color: "bg-blue-50 text-blue-700", icon: Settings },
      "Post Approval": { color: "bg-green-50 text-green-700", icon: CheckCircle },
      "Ticket Resolution": { color: "bg-purple-50 text-purple-700", icon: CheckCircle },
      "System Settings": { color: "bg-yellow-50 text-yellow-700", icon: Settings },
    };
    const { color, icon: Icon } = config[action] || { color: "bg-slate-50 text-slate-700", icon: Settings };
    return (
      <Badge variant="secondary" className={color}>
        <Icon className="w-3 h-3 mr-1" />
        {action}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">System Permissions & Operation Logs</h2>
        <p className="text-slate-500 mt-1">Manage admin accounts, permissions, and monitor all system operations</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Active Admins</p>
                <p className="text-2xl font-bold">12</p>
                <p className="text-xs text-slate-500 mt-1">Currently active</p>
              </div>
              <User className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Today's Operations</p>
                <p className="text-2xl font-bold">284</p>
                <p className="text-xs text-green-600 mt-1">+18.2% vs yesterday</p>
              </div>
              <Settings className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Critical Actions</p>
                <p className="text-2xl font-bold">23</p>
                <p className="text-xs text-red-600 mt-1">Requires monitoring</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">System Security</p>
                <p className="text-2xl font-bold">Secure</p>
                <p className="text-xs text-green-600 mt-1">All systems normal</p>
              </div>
              <Lock className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Admin Management Section */}
      <Card>
        <CardHeader>
          <div className="flex justify-between items-center">
            <CardTitle>Administrator Accounts</CardTitle>
            <Button size="sm">
              <User className="w-4 h-4 mr-2" />
              Add New Admin
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Admin ID</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Permissions</TableHead>
                <TableHead>Last Login</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {adminUsers.map((admin) => (
                <TableRow key={admin.id}>
                  <TableCell className="font-mono text-sm">{admin.adminId}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-8 w-8">
                        <AvatarFallback>{admin.name[0]}</AvatarFallback>
                      </Avatar>
                      <span className="font-medium">{admin.name}</span>
                    </div>
                  </TableCell>
                  <TableCell className="text-slate-600">{admin.email}</TableCell>
                  <TableCell>
                    <RoleBadge role={admin.role} />
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={admin.status} />
                  </TableCell>
                  <TableCell>
                    <div className="flex flex-wrap gap-1">
                      {admin.permissions.map((perm, idx) => (
                        <Badge key={idx} variant="secondary" className="bg-slate-100 text-slate-700 text-xs">
                          {perm}
                        </Badge>
                      ))}
                    </div>
                  </TableCell>
                  <TableCell className="text-slate-500 text-sm">{admin.lastLogin}</TableCell>
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
                          <Edit className="w-4 h-4 mr-2" />
                          Edit Permissions
                        </DropdownMenuItem>
                        {admin.status === 'active' && (
                          <DropdownMenuItem className="text-red-600">
                            Disable Account
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

      {/* Operation Logs Section */}
      <Card>
        <CardHeader>
          <CardTitle>Operation Audit Logs ({operationLogs.length} recent records)</CardTitle>
        </CardHeader>
        <CardContent>
          {/* Filter Section */}
          <div className="flex flex-wrap gap-4 mb-6 pb-6 border-b">
            <div className="flex-1 min-w-[200px]">
              <div className="relative">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
                <Input placeholder="Search admin / action / target..." className="pl-9" />
              </div>
            </div>
            <Select defaultValue="all">
              <SelectTrigger className="w-[160px]">
                <SelectValue placeholder="Action Type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Actions</SelectItem>
                <SelectItem value="ban">User Ban</SelectItem>
                <SelectItem value="content">Content Management</SelectItem>
                <SelectItem value="payment">Payment Operations</SelectItem>
                <SelectItem value="settings">System Settings</SelectItem>
              </SelectContent>
            </Select>
            <Select defaultValue="all">
              <SelectTrigger className="w-[160px]">
                <SelectValue placeholder="Admin" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Admins</SelectItem>
                <SelectItem value="a001">Admin Zhang</SelectItem>
                <SelectItem value="a002">Support Li</SelectItem>
                <SelectItem value="a003">Finance Wang</SelectItem>
              </SelectContent>
            </Select>
            <Button>Search</Button>
            <Button variant="outline">Export Logs</Button>
          </div>

          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[140px]">Log ID</TableHead>
                <TableHead>Admin</TableHead>
                <TableHead>Action Type</TableHead>
                <TableHead>Target</TableHead>
                <TableHead>Result</TableHead>
                <TableHead>IP Address</TableHead>
                <TableHead>Timestamp</TableHead>
                <TableHead className="max-w-[200px]">Details</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {operationLogs.map((log) => (
                <TableRow key={log.id}>
                  <TableCell className="font-mono text-sm">{log.logId}</TableCell>
                  <TableCell>
                    <div>
                      <div className="font-medium text-sm">{log.adminName}</div>
                      <div className="text-xs text-slate-500">{log.adminId}</div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <ActionBadge action={log.action} />
                  </TableCell>
                  <TableCell className="text-sm text-slate-600">{log.target}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className="bg-green-100 text-green-700 border-green-200">
                      <CheckCircle className="w-3 h-3 mr-1" />
                      {log.result}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-mono text-sm text-slate-500">{log.ip}</TableCell>
                  <TableCell className="text-slate-500 text-sm">{log.timestamp}</TableCell>
                  <TableCell className="max-w-[200px] text-sm text-slate-600 truncate">{log.details}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="sm">
                      <Eye className="w-4 h-4 mr-2" />
                      Details
                    </Button>
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
