import React, { useState } from 'react';
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { Label } from "../ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { AlertCircle, Loader2 } from "lucide-react";
import Logo from "../../imports/Logo";

interface LoginProps {
  onLogin: (email: string, password: string) => Promise<boolean>;
}

export const Login = ({ onLogin }: LoginProps) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const success = await onLogin(email, password);
      if (!success) {
        setError('邮箱或密码错误');
      }
    } catch (err) {
      setError('登录失败，请稍后重试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-950 px-4">
      {/* Background pattern */}
      <div className="absolute inset-0 bg-[linear-gradient(to_right,#1f1f1f_1px,transparent_1px),linear-gradient(to_bottom,#1f1f1f_1px,transparent_1px)] bg-[size:4rem_4rem] opacity-20" />

      <Card className="w-full max-w-md relative z-10 border-slate-800 bg-slate-900/90 backdrop-blur">
        <CardHeader className="space-y-4 text-center">
          <div className="w-16 h-16 mx-auto bg-red-600 rounded-lg p-3">
            <Logo />
          </div>
          <div>
            <CardTitle className="text-2xl font-bold text-white">ICERED ADMIN</CardTitle>
            <CardDescription className="text-slate-400 mt-2">
              Nova 后台管理系统
            </CardDescription>
          </div>
        </CardHeader>

        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {error && (
              <div className="bg-red-900/30 border border-red-800 text-red-400 px-4 py-3 rounded-lg flex items-center text-sm">
                <AlertCircle className="h-4 w-4 mr-2 flex-shrink-0" />
                {error}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="email" className="text-slate-300">邮箱</Label>
              <Input
                id="email"
                type="email"
                placeholder="admin@nova.app"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="bg-slate-800 border-slate-700 text-white placeholder:text-slate-500 focus:border-red-500 focus:ring-red-500"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password" className="text-slate-300">密码</Label>
              <Input
                id="password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="bg-slate-800 border-slate-700 text-white placeholder:text-slate-500 focus:border-red-500 focus:ring-red-500"
                required
              />
            </div>

            <Button
              type="submit"
              className="w-full bg-red-600 hover:bg-red-700 text-white"
              disabled={loading}
            >
              {loading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  登录中...
                </>
              ) : (
                '登录'
              )}
            </Button>
          </form>

          <div className="mt-6 pt-6 border-t border-slate-800">
            <p className="text-center text-sm text-slate-500">
              测试账号: admin@nova.app / Admin@2026
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
