import React, { useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "../ui/card";
import { Search, Eye, CheckCircle, XCircle, Clock, BadgeCheck, Briefcase, GraduationCap, FileText, AlertTriangle } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";

// Mock Data
const verifications = [
  { id: 1, userId: "U89230482", userName: "Alex Chen", type: "identity", idNumber: "4401********1234", status: "approved", submittedDate: "2024-01-05 10:30", reviewedDate: "2024-01-05 11:45", reviewer: "Admin01", documents: 3 },
  { id: 2, userId: "U89230483", userName: "Sarah Wu", type: "career", company: "TechCorp Inc.", position: "Senior Engineer", status: "pending", submittedDate: "2024-01-05 09:15", reviewedDate: "-", reviewer: "-", documents: 2 },
  { id: 3, userId: "U89230484", userName: "Mike Wang", type: "identity", idNumber: "3101********5678", status: "rejected", submittedDate: "2024-01-04 16:20", reviewedDate: "2024-01-04 18:30", reviewer: "Admin02", documents: 2 },
  { id: 4, userId: "U89230485", userName: "Lisa Li", type: "education", institution: "MIT", degree: "Master of CS", status: "approved", submittedDate: "2024-01-04 14:00", reviewedDate: "2024-01-04 15:20", reviewer: "Admin01", documents: 4 },
  { id: 5, userId: "U89230486", userName: "Tom Zhang", type: "career", company: "StartupX", position: "Product Manager", status: "pending", submittedDate: "2024-01-04 11:45", reviewedDate: "-", reviewer: "-", documents: 3 },
  { id: 6, userId: "U89230487", userName: "Emily Wang", type: "identity", idNumber: "5001********9012", status: "approved", submittedDate: "2024-01-03 13:20", reviewedDate: "2024-01-03 14:50", reviewer: "Admin03", documents: 3 },
  { id: 7, userId: "U89230488", userName: "David Liu", type: "education", institution: "Stanford", degree: "PhD in AI", status: "pending", submittedDate: "2024-01-03 10:00", reviewedDate: "-", reviewer: "-", documents: 5 },
];

export const VerificationCenter = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string; icon: any }> = {
      approved: { bg: "bg-green-100 text-green-700 border-green-200", text: "Approved", icon: CheckCircle },
      pending: { bg: "bg-yellow-100 text-yellow-700 border-yellow-200", text: "Pending Review", icon: Clock },
      rejected: { bg: "bg-red-100 text-red-700 border-red-200", text: "Rejected", icon: XCircle },
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

  const TypeBadge = ({ type }: { type: string }) => {
    const config: Record<string, { icon: any; color: string }> = {
      identity: { icon: BadgeCheck, color: "bg-blue-50 text-blue-700" },
      career: { icon: Briefcase, color: "bg-purple-50 text-purple-700" },
      education: { icon: GraduationCap, color: "bg-green-50 text-green-700" },
    };
    const { icon: Icon, color } = config[type];
    return (
      <Badge variant="secondary" className={color}>
        <Icon className="w-3 h-3 mr-1" />
        {type.charAt(0).toUpperCase() + type.slice(1)}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">Identity & Career Verification</h2>
        <p className="text-slate-500 mt-1">Review and approve user identity, career, and education verification requests</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Pending Review</p>
                <p className="text-2xl font-bold text-yellow-600">23</p>
                <p className="text-xs text-slate-500 mt-1">Requires action</p>
              </div>
              <Clock className="h-8 w-8 text-yellow-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Approved Today</p>
                <p className="text-2xl font-bold text-green-600">87</p>
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
                <p className="text-sm text-slate-500">Rejected Today</p>
                <p className="text-2xl font-bold text-red-600">12</p>
                <p className="text-xs text-slate-500 mt-1">Quality control</p>
              </div>
              <XCircle className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Total Verified</p>
                <p className="text-2xl font-bold">12,845</p>
                <p className="text-xs text-slate-500 mt-1">All time</p>
              </div>
              <BadgeCheck className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Avg Review Time</p>
                <p className="text-2xl font-bold">2.4h</p>
                <p className="text-xs text-green-600 mt-1">-0.5h improvement</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-slate-400" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search user / ID / document number..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder="Verification Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Types</SelectItem>
            <SelectItem value="identity">Identity Verification</SelectItem>
            <SelectItem value="career">Career Verification</SelectItem>
            <SelectItem value="education">Education Verification</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="approved">Approved</SelectItem>
            <SelectItem value="rejected">Rejected</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Export Report</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Verification Requests ({verifications.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[100px]">Request ID</TableHead>
                <TableHead>User</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Verification Details</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Documents</TableHead>
                <TableHead>Submitted Time</TableHead>
                <TableHead>Reviewer</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {verifications.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{`VR${item.id.toString().padStart(6, '0')}`}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-8 w-8">
                        <AvatarFallback>{item.userName[0]}</AvatarFallback>
                      </Avatar>
                      <div>
                        <div className="font-medium">{item.userName}</div>
                        <div className="text-xs text-slate-500">{item.userId}</div>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <TypeBadge type={item.type} />
                  </TableCell>
                  <TableCell>
                    <div className="text-sm">
                      {item.type === 'identity' && (
                        <div className="font-mono text-slate-600">ID: {item.idNumber}</div>
                      )}
                      {item.type === 'career' && (
                        <div>
                          <div className="font-medium">{item.position}</div>
                          <div className="text-xs text-slate-500">{item.company}</div>
                        </div>
                      )}
                      {item.type === 'education' && (
                        <div>
                          <div className="font-medium">{item.degree}</div>
                          <div className="text-xs text-slate-500">{item.institution}</div>
                        </div>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline" className="bg-slate-50">
                      <FileText className="w-3 h-3 mr-1" />
                      {item.documents} files
                    </Badge>
                  </TableCell>
                  <TableCell className="text-slate-500 text-sm">{item.submittedDate}</TableCell>
                  <TableCell className="text-sm">
                    {item.reviewer !== '-' ? (
                      <span className="text-slate-600">{item.reviewer}</span>
                    ) : (
                      <span className="text-slate-400">Unassigned</span>
                    )}
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
                          View Documents
                        </DropdownMenuItem>
                        {item.status === 'pending' && (
                          <>
                            <DropdownMenuItem className="text-green-600">
                              <CheckCircle className="w-4 h-4 mr-2" />
                              Approve
                            </DropdownMenuItem>
                            <DropdownMenuItem className="text-red-600">
                              <XCircle className="w-4 h-4 mr-2" />
                              Reject
                            </DropdownMenuItem>
                          </>
                        )}
                        <DropdownMenuItem>
                          <FileText className="w-4 h-4 mr-2" />
                          Download Files
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
