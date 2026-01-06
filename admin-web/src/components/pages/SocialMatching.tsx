import React from 'react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "../ui/card";
import { Search, Heart, UserX, TrendingUp, Users, MessageCircle, Zap, Eye } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";

// Mock Data
const matches = [
  { id: 1, user1: "Alex Chen", user1Id: "U89230482", user2: "Jessica Wu", user2Id: "U89230490", matchScore: 92, status: "active", source: "AI Recommendation", messages: 156, startDate: "2024-01-03", lastActive: "2 hours ago" },
  { id: 2, user1: "Sarah Wu", user1Id: "U89230483", user2: "Mike Wang", user2Id: "U89230484", matchScore: 78, status: "inactive", source: "Deepsearch", messages: 23, startDate: "2024-01-02", lastActive: "2 days ago" },
  { id: 3, user1: "Lisa Li", user1Id: "U89230485", user2: "Tom Zhang", user2Id: "U89230486", matchScore: 88, status: "active", source: "Home Feed", messages: 89, startDate: "2024-01-01", lastActive: "30 mins ago" },
  { id: 4, user1: "Emily Wang", user1Id: "U89230487", user2: "David Liu", user2Id: "U89230488", matchScore: 95, status: "active", source: "AI Recommendation", messages: 234, startDate: "2023-12-28", lastActive: "1 hour ago" },
  { id: 5, user1: "Kevin Zhang", user1Id: "U89230491", user2: "Anna Li", user2Id: "U89230492", matchScore: 65, status: "unmatched", source: "Mutual Friends", messages: 8, startDate: "2023-12-25", lastActive: "5 days ago" },
  { id: 6, user1: "Brian Chen", user1Id: "U89230493", user2: "Rachel Wang", user2Id: "U89230494", matchScore: 82, status: "active", source: "Deepsearch", messages: 67, startDate: "2023-12-20", lastActive: "3 hours ago" },
  { id: 7, user1: "Jason Wu", user1Id: "U89230495", user2: "Sophia Liu", user2Id: "U89230496", matchScore: 91, status: "active", source: "AI Recommendation", messages: 178, startDate: "2023-12-15", lastActive: "15 mins ago" },
];

export const SocialMatching = () => {
  const StatusBadge = ({ status }: { status: string }) => {
    const styles: Record<string, { bg: string; text: string }> = {
      active: { bg: "bg-green-100 text-green-700 border-green-200", text: "Active Chat" },
      inactive: { bg: "bg-slate-100 text-slate-600 border-slate-200", text: "Inactive" },
      unmatched: { bg: "bg-red-100 text-red-700 border-red-200", text: "Unmatched" },
    };
    const style = styles[status];
    return <Badge variant="outline" className={style.bg}>{style.text}</Badge>;
  };

  const MatchScoreBadge = ({ score }: { score: number }) => {
    let color = "bg-slate-100 text-slate-700";
    if (score >= 90) color = "bg-red-100 text-red-700 border-red-200";
    else if (score >= 75) color = "bg-green-100 text-green-700 border-green-200";
    else if (score >= 60) color = "bg-yellow-100 text-yellow-700 border-yellow-200";
    
    return (
      <Badge variant="outline" className={color}>
        {score}% Match
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-slate-900">Social Relationship & Matching</h2>
        <p className="text-slate-500 mt-1">Manage and monitor user matching algorithms and social connections</p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Active Matches</p>
                <p className="text-2xl font-bold">2,847</p>
                <p className="text-xs text-green-600 mt-1">+18.5% vs last week</p>
              </div>
              <Heart className="h-8 w-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">New Matches Today</p>
                <p className="text-2xl font-bold">573</p>
                <p className="text-xs text-slate-500 mt-1">Above average</p>
              </div>
              <Users className="h-8 w-8 text-blue-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Unmatched Today</p>
                <p className="text-2xl font-bold">89</p>
                <p className="text-xs text-slate-500 mt-1">Natural churn</p>
              </div>
              <UserX className="h-8 w-8 text-slate-400" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Avg Match Score</p>
                <p className="text-2xl font-bold">84%</p>
                <p className="text-xs text-green-600 mt-1">+3% improvement</p>
              </div>
              <TrendingUp className="h-8 w-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-500">Messages Sent</p>
                <p className="text-2xl font-bold">48,291</p>
                <p className="text-xs text-slate-500 mt-1">Last 24 hours</p>
              </div>
              <MessageCircle className="h-8 w-8 text-purple-500" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filter Section */}
      <div className="flex flex-wrap gap-4 bg-white p-4 rounded-lg border border-slate-200 shadow-sm">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
            <Input placeholder="Search user names / IDs..." className="pl-9" />
          </div>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Match Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Status</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="inactive">Inactive</SelectItem>
            <SelectItem value="unmatched">Unmatched</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Match Source" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Sources</SelectItem>
            <SelectItem value="ai">AI Recommendation</SelectItem>
            <SelectItem value="deepsearch">Deepsearch</SelectItem>
            <SelectItem value="feed">Home Feed</SelectItem>
            <SelectItem value="mutual">Mutual Friends</SelectItem>
          </SelectContent>
        </Select>
        <Select defaultValue="all">
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="Match Score" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Scores</SelectItem>
            <SelectItem value="high">High (90%+)</SelectItem>
            <SelectItem value="medium">Medium (70-89%)</SelectItem>
            <SelectItem value="low">Low (&lt;70%)</SelectItem>
          </SelectContent>
        </Select>
        <Button>Search</Button>
        <Button variant="outline">Analytics Report</Button>
      </div>

      {/* Data Display Table */}
      <Card>
        <CardHeader>
          <CardTitle>Active Matches ({matches.length} records)</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[100px]">Match ID</TableHead>
                <TableHead>User 1</TableHead>
                <TableHead>User 2</TableHead>
                <TableHead>Match Score</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Source</TableHead>
                <TableHead>Messages</TableHead>
                <TableHead>Start Date</TableHead>
                <TableHead>Last Active</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {matches.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono text-sm">{`M${item.id.toString().padStart(6, '0')}`}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-8 w-8">
                        <AvatarFallback>{item.user1[0]}</AvatarFallback>
                      </Avatar>
                      <div>
                        <div className="font-medium text-sm">{item.user1}</div>
                        <div className="text-xs text-slate-500">{item.user1Id}</div>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Avatar className="h-8 w-8">
                        <AvatarFallback>{item.user2[0]}</AvatarFallback>
                      </Avatar>
                      <div>
                        <div className="font-medium text-sm">{item.user2}</div>
                        <div className="text-xs text-slate-500">{item.user2Id}</div>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <MatchScoreBadge score={item.matchScore} />
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={item.status} />
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="bg-purple-50 text-purple-700">
                      <Zap className="w-3 h-3 mr-1" />
                      {item.source}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <MessageCircle className="w-4 h-4 text-slate-400" />
                      <span className="text-sm">{item.messages}</span>
                    </div>
                  </TableCell>
                  <TableCell className="text-slate-500 text-sm">{item.startDate}</TableCell>
                  <TableCell className="text-slate-500 text-sm">{item.lastActive}</TableCell>
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
                          View Chat History
                        </DropdownMenuItem>
                        <DropdownMenuItem>
                          <TrendingUp className="w-4 h-4 mr-2" />
                          View Analytics
                        </DropdownMenuItem>
                        <DropdownMenuItem className="text-red-600">
                          <UserX className="w-4 h-4 mr-2" />
                          Force Unmatch
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
