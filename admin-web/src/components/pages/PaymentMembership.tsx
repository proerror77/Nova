import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "../ui/card";
import { Search, CreditCard, DollarSign, CheckCircle, XCircle, AlertCircle, Crown, Eye, RefreshCw } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { PieChart, Pie, Cell, ResponsiveContainer, Legend, Tooltip } from 'recharts';

// Mock Data
const transactions = [
  { id: 1, orderId: "ORD20240105001", userId: "U89230482", userName: "Alex Chen", type: "Premium Upgrade", amount: "$29.99", status: "completed", method: "Credit Card", date: "2024-01-05 14:23", membership: "Premium Monthly" },
  { id: 2, orderId: "ORD20240105002", userId: "U89230483", userName: "Sarah Wu", type: "Gift Purchase", amount: "$9.99", status: "completed", method: "PayPal", date: "2024-01-05 13:45", membership: "-" },
  { id: 3, orderId: "ORD20240105003", userId: "U89230484", userName: "Mike Wang", type: "VIP Upgrade", amount: "$99.99", status: "pending", method: "Credit Card", date: "2024-01-05 12:30", membership: "VIP Annual" },
  { id: 4, orderId: "ORD20240105004", userId: "U89230485", userName: "Lisa Li", type: "Renewal", amount: "$29.99", status: "completed", method: "Alipay", date: "2024-01-05 11:15", membership: "Premium Monthly" },
  { id: 5, orderId: "ORD20240105005", userId: "U89230486", userName: "Tom Zhang", type: "Premium Upgrade", amount: "$79.99", status: "failed", method: "Credit Card", date: "2024-01-05 10:20", membership: "Premium Annual" },
  { id: 6, orderId: "ORD20240104001", userId: "U89230487", userName: "Emily Wang", type: "Boost Purchase", amount: "$4.99", status: "completed", method: "Apple Pay", date: "2024-01-04 18:45", membership: "-" },
  { id: 7, orderId: "ORD20240104002", userId: "U89230488", userName: "David Liu", type: "VIP Upgrade", amount: "$99.99", status: "completed", method: "Credit Card", date: "2024-01-04 16:30", membership: "VIP Annual" },
];

const revenueData = [
  { name: 'Premium Monthly', value: 45, color: '#dc2626' },
  { name: 'Premium Annual', value: 25, color: '#000000' },
  { name: 'VIP Annual', value: 20, color: '#f59e0b' },
  { name: 'In-app Purchases', value: 10, color: '#64748b' },
];

export const PaymentMembership = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; icon: any }> = {
      completed: { bg: "bg-green-100 text-green-700 border-green-200", icon: CheckCircle },
      pending: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", icon: AlertCircle },
      failed: { bg: "bg-red-100 text-red-700 border-red-200", icon: XCircle },
      refunded: { bg: "bg-slate-100 text-slate-600 border-slate-200", icon: RefreshCw },
    };
    const style = styles[status];
    const Icon = style.icon;
    return (
      <Badge variant="outline" className={style.bg}>
        <Icon className="w-3 h-3 mr-1" />
        {status.toUpperCase()}
      </Badge>
    );
  };

  const MethodBadge = ({ method }: { method: string }) => {
    const colors: Record<string, string> = {
      "Credit Card": "bg-blue-50 text-blue-700",
      "PayPal": "bg-purple-50 text-purple-700",
      "Alipay": "bg-cyan-50 text-cyan-700",
      "Apple Pay": "bg-slate-50 text-slate-700",
    };
    return (
      <Badge variant="secondary" className={colors[method] || "bg-slate-50 text-slate-700"}>
        {method}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">Payment & Membership Management</h2>
        <p className="text-slate-500 mt-1">Monitor transactions, subscriptions, and revenue analytics</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Today's Revenue</p>
                <p className="text-2xl font-bold">$8,492</p>
                <p className="text-xs text-green-600 mt-1">+28.4% vs yesterday</p>
              </div>
              <DollarSign className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Active Members</p>
                <p className="text-2xl font-bold">12,845</p>
                <p className="text-xs text-slate-500 mt-1">Premium & VIP users</p>
              </div>
              <Crown className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Transactions Today</p>
                <p className="text-2xl font-bold">284</p>
                <p className="text-xs text-green-600 mt-1">+12.3% vs yesterday</p>
              </div>
              <CreditCard className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Success Rate</p>
                <p className="text-2xl font-bold">97.8%</p>
                <p className="text-xs text-slate-500 mt-1">Payment completion</p>
              </div>
              <CheckCircle className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Failed Payments</p>
                <p className="text-2xl font-bold">23</p>
                <p className="text-xs text-red-600 mt-1">Requires attention</p>
              </div>
              <XCircle className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Revenue Breakdown */}
      <Card>
        <CardHeader>
          <CardTitle>Revenue Distribution by Membership Tier</CardTitle>
          <CardDescription>Monthly recurring revenue breakdown</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie
                  data={revenueData}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {revenueData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
            <div className="space-y-4 ml-8">
              <div className="flex items-center gap-3">
                <div className="w-4 h-4 bg-red-600 rounded"></div>
                <div>
                  <p className="text-sm font-medium">Premium Monthly</p>
                  <p className="text-xs text-slate-500">$29.99/month × 5,780 users</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-4 h-4 bg-black rounded"></div>
                <div>
                  <p className="text-sm font-medium">Premium Annual</p>
                  <p className="text-xs text-slate-500">$279.99/year × 3,210 users</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-4 h-4 bg-yellow-500 rounded"></div>
                <div>
                  <p className="text-sm font-medium">VIP Annual</p>
                  <p className="text-xs text-slate-500">$999.99/year × 856 users</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-4 h-4 bg-slate-500 rounded"></div>
                <div>
                  <p className="text-sm font-medium">In-app Purchases</p>
                  <p className="text-xs text-slate-500">Boosts, Gifts, Features</p>
                </div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search order ID / user / transaction..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Payment Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="failed">Failed</SelectItem>
            <SelectItem value="refunded">Refunded</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Payment Method" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Methods</SelectItem>
            <SelectItem value="card">Credit Card</SelectItem>
            <SelectItem value="paypal">PayPal</SelectItem>
            <SelectItem value="alipay">Alipay</SelectItem>
            <SelectItem value="apple">Apple Pay</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Transaction Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            <SelectItem value="upgrade">Upgrade</SelectItem>
            <SelectItem value="renewal">Renewal</SelectItem>
            <SelectItem value="purchase">Purchase</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Export Report</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Transactions ({transactions.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[140px]">Order ID</TableHead>
                <TableHead>User</TableHead>
                <TableHead>Transaction Type</TableHead>
                <TableHead>Amount</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Payment Method</TableHead>
                <TableHead>Membership</TableHead>
                <TableHead>Transaction Time</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {transactions.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{item.orderId}</TableCell>
                  <TableCell>
                    <div>
                      <div className="font-medium">{item.userName}</div>
                      <div className="text-xs text-slate-500">{item.userId}</div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="bg-blue-50 text-blue-700">
                      {item.type}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-bold text-green-600">{item.amount}</TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell>
                    <MethodBadge method={item.method} />
                  </TableCell>
                  <TableCell>
                    {item.membership !== '-' ? (
                      <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">
                        <Crown className="w-3 h-3 mr-1" />
                        {item.membership}
                      </Badge>
                    ) : (
                      <span className="text-slate-400 text-sm">-</span>
                    )}
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
                          View Details
                        </DropdownMenuItem>
                        {item.status === 'completed' && (
                          <DropdownMenuItem className="text-red-600">
                            <RefreshCw className="w-4 h-4 mr-2" />
                            Process Refund
                          </DropdownMenuItem>
                        )}
                        {item.status === 'failed' && (
                          <DropdownMenuItem className="text-blue-600">
                            <RefreshCw className="w-4 h-4 mr-2" />
                            Retry Payment
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem>
                          Download Invoice
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
