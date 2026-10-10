#!/usr/bin/env node
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const registryPath = join(root, "registry.json");
const registryDir = join(root, "registry", "blocks");
const force = process.argv.includes("--force");

function titleize(name) {
  return name
    .split("-")
    .map((part) => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}

function block(name, description, registryDependencies, source, extra = {}) {
  return {
    name,
    description,
    registryDependencies,
    dependencies: extra.dependencies || (source.includes('from "lucide-react"') ? ["lucide-react"] : []),
    source,
  };
}

const blocks = [
  block(
    "app-shell-sidebar",
    "Responsive app shell with sidebar, top bar, workspace switcher, search, nav groups, user menu slot, and content area.",
    ["sidebar", "button", "badge", "separator", "dropdown-menu", "avatar", "input"],
    `import type { ReactNode } from "react"
import {
  Bell,
  ChevronDown,
  LayoutDashboard,
  MessageSquare,
  Search,
  Settings,
  Sparkles,
} from "lucide-react"

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"

const navItems = [
  { title: "Dashboard", icon: LayoutDashboard, href: "#" },
  { title: "Chat", icon: MessageSquare, href: "#" },
  { title: "Automations", icon: Sparkles, href: "#", badge: "New" },
  { title: "Settings", icon: Settings, href: "#" },
]

export function AppShellSidebar({ children }: { children?: ReactNode }) {
  return (
    <SidebarProvider>
      <Sidebar collapsible="icon">
        <SidebarHeader>
          <div className="flex items-center gap-2 px-2 py-1.5">
            <div className="grid size-8 place-items-center rounded-md bg-primary text-primary-foreground">A</div>
            <div className="min-w-0 group-data-[collapsible=icon]:hidden">
              <div className="truncate text-sm font-medium">Acme Workspace</div>
              <div className="truncate text-xs text-muted-foreground">Production</div>
            </div>
          </div>
        </SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Workspace</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {navItems.map((item) => (
                  <SidebarMenuItem key={item.title}>
                    <SidebarMenuButton asChild tooltip={item.title}>
                      <a href={item.href}>
                        <item.icon />
                        <span>{item.title}</span>
                        {item.badge ? <Badge className="ml-auto">{item.badge}</Badge> : null}
                      </a>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        </SidebarContent>
        <SidebarFooter>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="w-full justify-start gap-2 px-2">
                <Avatar className="size-7">
                  <AvatarImage src="" alt="" />
                  <AvatarFallback>SG</AvatarFallback>
                </Avatar>
                <span className="truncate group-data-[collapsible=icon]:hidden">Sagar</span>
                <ChevronDown className="ml-auto size-4 group-data-[collapsible=icon]:hidden" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>Account</DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem>Profile</DropdownMenuItem>
              <DropdownMenuItem>Billing</DropdownMenuItem>
              <DropdownMenuItem>Sign out</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset>
        <header className="flex h-14 items-center gap-3 border-b px-4">
          <SidebarTrigger />
          <Separator orientation="vertical" className="h-5" />
          <div className="relative hidden flex-1 md:block">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input className="max-w-md pl-9" placeholder="Search..." />
          </div>
          <Button variant="ghost" size="icon" className="ml-auto">
            <Bell className="size-4" />
          </Button>
        </header>
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </SidebarInset>
    </SidebarProvider>
  )
}
`
  ),
  block(
    "auth-clerk-shell",
    "Clerk-ready auth shell UI with split layout, social/login slots, and backend integration points.",
    ["button", "card", "input", "label", "separator"],
    `import { ArrowRight } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"

export function AuthClerkShell() {
  return (
    <div className="grid min-h-screen bg-background lg:grid-cols-[1.1fr_0.9fr]">
      <section className="hidden flex-col justify-between border-r bg-muted/30 p-10 lg:flex">
        <div className="text-sm font-medium">Acme</div>
        <div className="max-w-xl space-y-4">
          <h1 className="text-4xl font-semibold tracking-tight">A focused workspace for shipping faster.</h1>
          <p className="text-lg text-muted-foreground">
            Replace this panel with product proof, security notes, or customer-specific onboarding copy.
          </p>
        </div>
        <p className="text-sm text-muted-foreground">Trusted authentication. Source-owned UI.</p>
      </section>
      <section className="flex items-center justify-center p-6">
        <Card className="w-full max-w-md border-none shadow-none lg:border lg:shadow-sm">
          <CardHeader>
            <CardTitle>Sign in</CardTitle>
            <CardDescription>Connect Clerk here, or swap in any backend auth provider.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button className="w-full" variant="outline">Continue with Google</Button>
            <div className="flex items-center gap-3">
              <Separator className="flex-1" />
              <span className="text-xs text-muted-foreground">or</span>
              <Separator className="flex-1" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" placeholder="you@company.com" />
            </div>
            <Button className="w-full">
              Continue <ArrowRight className="ml-2 size-4" />
            </Button>
            <p className="text-center text-xs text-muted-foreground">
              Clerk integration point: replace this form with SignIn or SignInButton when wiring auth.
            </p>
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
`
  ),
  block(
    "chat-shell",
    "Responsive chat application shell with conversation sidebar, message area, composer, and assistant status.",
    ["avatar", "badge", "button", "input", "scroll-area", "separator", "textarea"],
    `import { MoreHorizontal, PanelLeft, Plus, Send } from "lucide-react"

import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"

const threads = ["Research brief", "Client onboarding", "Map analysis", "Pricing review"]
const messages = [
  { role: "assistant", body: "I found three viable directions. The map-heavy option needs MapLibre." },
  { role: "user", body: "Start with the leanest one and keep the UI production-shaped." },
]

export function ChatShell() {
  return (
    <div className="grid h-screen bg-background md:grid-cols-[280px_1fr]">
      <aside className="hidden border-r md:block">
        <div className="flex h-14 items-center gap-2 px-3">
          <Button size="sm" className="w-full justify-start">
            <Plus className="mr-2 size-4" /> New chat
          </Button>
        </div>
        <Separator />
        <div className="p-3">
          <Input placeholder="Search conversations" />
        </div>
        <ScrollArea className="h-[calc(100vh-112px)]">
          <div className="space-y-1 p-2">
            {threads.map((thread, index) => (
              <Button key={thread} variant={index === 0 ? "secondary" : "ghost"} className="w-full justify-start">
                {thread}
                {index === 0 ? <Badge className="ml-auto">Live</Badge> : null}
              </Button>
            ))}
          </div>
        </ScrollArea>
      </aside>
      <main className="flex min-w-0 flex-col">
        <header className="flex h-14 items-center gap-2 border-b px-4">
          <Button variant="ghost" size="icon" className="md:hidden">
            <PanelLeft className="size-4" />
          </Button>
          <div className="min-w-0">
            <div className="truncate text-sm font-medium">Research brief</div>
            <div className="text-xs text-muted-foreground">Assistant ready</div>
          </div>
          <Button variant="ghost" size="icon" className="ml-auto">
            <MoreHorizontal className="size-4" />
          </Button>
        </header>
        <ScrollArea className="flex-1">
          <div className="mx-auto flex w-full max-w-3xl flex-col gap-4 p-4 md:p-6">
            {messages.map((message, index) => (
              <div key={index} className="flex gap-3">
                <Avatar className="size-8">
                  <AvatarFallback>{message.role === "assistant" ? "AI" : "U"}</AvatarFallback>
                </Avatar>
                <div className="rounded-lg border bg-card p-3 text-sm shadow-sm">{message.body}</div>
              </div>
            ))}
          </div>
        </ScrollArea>
        <div className="border-t p-4">
          <div className="mx-auto flex max-w-3xl gap-2">
            <Textarea className="min-h-12 resize-none" placeholder="Message..." />
            <Button size="icon" className="h-12 w-12">
              <Send className="size-4" />
            </Button>
          </div>
        </div>
      </main>
    </div>
  )
}
`
  ),
  block(
    "dashboard-overview",
    "Dashboard overview with responsive KPI cards, activity list, chart placeholder, and action rail.",
    ["badge", "button", "card", "separator"],
    `import { ArrowUpRight, TrendingUp } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"

const stats = [
  { label: "Revenue", value: "$48.2k", delta: "+12%" },
  { label: "Active users", value: "8,421", delta: "+8%" },
  { label: "Conversion", value: "6.8%", delta: "+1.1%" },
]

export function DashboardOverview() {
  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
          <p className="text-sm text-muted-foreground">Replace demo metrics with product data.</p>
        </div>
        <Button>
          View report <ArrowUpRight className="ml-2 size-4" />
        </Button>
      </div>
      <div className="grid gap-4 md:grid-cols-3">
        {stats.map((stat) => (
          <Card key={stat.label}>
            <CardHeader className="pb-2">
              <CardDescription>{stat.label}</CardDescription>
              <CardTitle className="text-3xl">{stat.value}</CardTitle>
            </CardHeader>
            <CardContent>
              <Badge variant="secondary">
                <TrendingUp className="mr-1 size-3" /> {stat.delta}
              </Badge>
            </CardContent>
          </Card>
        ))}
      </div>
      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <Card>
          <CardHeader>
            <CardTitle>Trend</CardTitle>
            <CardDescription>Drop a chart component here when charting is actually required.</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid h-72 place-items-center rounded-md border border-dashed text-sm text-muted-foreground">
              Chart placeholder
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Activity</CardTitle>
            <CardDescription>Recent product events.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {["New workspace created", "Billing updated", "AI run completed"].map((item) => (
              <div key={item}>
                <div className="text-sm font-medium">{item}</div>
                <div className="text-xs text-muted-foreground">2 hours ago</div>
                <Separator className="mt-4" />
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
`
  ),
  block(
    "settings-shell",
    "Settings shell with responsive tabs, profile form layout, and connected account slots.",
    ["button", "card", "input", "label", "tabs", "textarea"],
    `import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"

export function SettingsShell() {
  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        <p className="text-sm text-muted-foreground">A reusable account/workspace settings surface.</p>
      </div>
      <Tabs defaultValue="profile" className="space-y-4">
        <TabsList className="w-full justify-start overflow-x-auto">
          <TabsTrigger value="profile">Profile</TabsTrigger>
          <TabsTrigger value="workspace">Workspace</TabsTrigger>
          <TabsTrigger value="security">Security</TabsTrigger>
        </TabsList>
        <TabsContent value="profile">
          <Card>
            <CardHeader>
              <CardTitle>Profile</CardTitle>
              <CardDescription>Wire these fields to your backend or Clerk profile data.</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label>Name</Label>
                <Input defaultValue="Sagar" />
              </div>
              <div className="space-y-2">
                <Label>Email</Label>
                <Input defaultValue="sagar@example.com" />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Bio</Label>
                <Textarea placeholder="Short profile note" />
              </div>
              <div className="md:col-span-2">
                <Button>Save changes</Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
`
  ),
  block(
    "billing-page",
    "Billing page shell with current plan, payment method, invoice list, and upgrade CTA.",
    ["badge", "button", "card", "table"],
    `import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"

const invoices = [
  { id: "INV-001", date: "Oct 01", amount: "$49.00", status: "Paid" },
  { id: "INV-002", date: "Sep 01", amount: "$49.00", status: "Paid" },
]

export function BillingPage() {
  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Billing</h1>
          <p className="text-sm text-muted-foreground">Connect this UI to Stripe, Lemon Squeezy, or your billing backend.</p>
        </div>
        <Button>Manage plan</Button>
      </div>
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Current plan</CardTitle>
            <CardDescription>Team plan</CardDescription>
          </CardHeader>
          <CardContent className="flex items-end justify-between">
            <div className="text-3xl font-semibold">$49/mo</div>
            <Badge>Active</Badge>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Payment method</CardTitle>
            <CardDescription>Visa ending in 4242</CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="outline">Update card</Button>
          </CardContent>
        </Card>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>Invoices</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Invoice</TableHead>
                <TableHead>Date</TableHead>
                <TableHead>Amount</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {invoices.map((invoice) => (
                <TableRow key={invoice.id}>
                  <TableCell>{invoice.id}</TableCell>
                  <TableCell>{invoice.date}</TableCell>
                  <TableCell>{invoice.amount}</TableCell>
                  <TableCell>{invoice.status}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
`
  ),
  block(
    "onboarding-flow",
    "Three-step onboarding UI with progress, selectable cards, and primary action.",
    ["button", "card", "progress", "radio-group"],
    `import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"

const goals = ["Build a dashboard", "Launch a chat app", "Analyze map data"]

export function OnboardingFlow() {
  return (
    <div className="mx-auto flex min-h-screen max-w-2xl flex-col justify-center p-6">
      <div className="mb-6 space-y-2">
        <div className="text-sm text-muted-foreground">Step 1 of 3</div>
        <Progress value={33} />
      </div>
      <Card>
        <CardHeader>
          <CardTitle>What are you building?</CardTitle>
          <CardDescription>Use this to route users into the right starter workflow.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <RadioGroup defaultValue={goals[0]}>
            {goals.map((goal) => (
              <label key={goal} className="flex cursor-pointer items-center gap-3 rounded-lg border p-4">
                <RadioGroupItem value={goal} />
                <span className="font-medium">{goal}</span>
              </label>
            ))}
          </RadioGroup>
          <Button className="w-full">Continue</Button>
        </CardContent>
      </Card>
    </div>
  )
}
`
  ),
  block(
    "data-table-toolbar",
    "Data table toolbar with search, filter, view options, bulk action slot, and export action.",
    ["button", "dropdown-menu", "input", "separator"],
    `import { Download, Filter, SlidersHorizontal } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"

export function DataTableToolbar() {
  return (
    <div className="flex flex-col gap-3 rounded-lg border bg-card p-3 md:flex-row md:items-center">
      <Input className="md:max-w-xs" placeholder="Search records..." />
      <div className="flex flex-wrap items-center gap-2 md:ml-auto">
        <Button variant="outline">
          <Filter className="mr-2 size-4" /> Filter
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline">
              <SlidersHorizontal className="mr-2 size-4" /> View
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuLabel>Columns</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuCheckboxItem checked>Name</DropdownMenuCheckboxItem>
            <DropdownMenuCheckboxItem checked>Status</DropdownMenuCheckboxItem>
            <DropdownMenuCheckboxItem>Owner</DropdownMenuCheckboxItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <Separator orientation="vertical" className="hidden h-6 md:block" />
        <Button variant="secondary">
          <Download className="mr-2 size-4" /> Export
        </Button>
      </div>
    </div>
  )
}
`
  ),
  block(
    "map-analysis-shell",
    "Map analysis shell with MapLibre canvas slot, filter rail, legend, scope stats, and map-only undo status line.",
    ["badge", "button", "card", "select", "separator"],
    `import { RotateCcw, Undo2 } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"

export function MapAnalysisShell() {
  return (
    <div className="grid h-screen bg-background lg:grid-cols-[320px_1fr]">
      <aside className="border-r p-4">
        <div className="space-y-1">
          <h1 className="text-lg font-semibold">Map analysis</h1>
          <p className="text-sm text-muted-foreground">MapLibre renders the canvas; shadcn renders controls.</p>
        </div>
        <Separator className="my-4" />
        <div className="space-y-4">
          <div className="space-y-2">
            <div className="text-sm font-medium">Level</div>
            <Select defaultValue="region">
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="region">Region</SelectItem>
                <SelectItem value="sa2">SA2</SelectItem>
                <SelectItem value="sa1">SA1</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Scope stats</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div className="flex justify-between"><span>Features</span><span>128</span></div>
              <div className="flex justify-between"><span>Population</span><span>1.2M</span></div>
              <Badge variant="secondary">Data vintage: 2026</Badge>
            </CardContent>
          </Card>
        </div>
      </aside>
      <main className="relative min-h-0">
        <div className="absolute inset-0 grid place-items-center bg-muted/30 text-sm text-muted-foreground">
          MapLibre canvas mounts here
        </div>
        <div className="absolute bottom-4 left-4 right-4 flex flex-wrap items-center gap-2 rounded-lg border bg-background/95 p-2 shadow-sm backdrop-blur">
          <span className="text-sm">Map updated: highlighted selected features</span>
          <Button variant="outline" size="sm" className="ml-auto">
            <Undo2 className="mr-2 size-4" /> Undo
          </Button>
          <Button variant="outline" size="sm">
            <RotateCcw className="mr-2 size-4" /> Reset
          </Button>
        </div>
      </main>
    </div>
  )
}
`
  ),
];

if (existsSync(registryPath) && !force) {
  console.error("registry.json already exists. Use --force to overwrite.");
  process.exit(1);
}

mkdirSync(registryDir, { recursive: true });

const registryItems = [];

for (const item of blocks) {
  const itemDir = join(registryDir, item.name);
  mkdirSync(itemDir, { recursive: true });
  const sourcePath = join(itemDir, `${item.name}.tsx`);
  writeFileSync(sourcePath, item.source.trimStart());

  registryItems.push({
    name: item.name,
    type: "registry:block",
    title: titleize(item.name),
    description: item.description,
    registryDependencies: item.registryDependencies,
    dependencies: item.dependencies,
    files: [
      {
        path: `registry/blocks/${item.name}/${item.name}.tsx`,
        type: "registry:component",
        target: `components/blocks/${item.name}.tsx`,
      },
    ],
  });
}

writeFileSync(
  registryPath,
  JSON.stringify(
    {
      "$schema": "https://ui.shadcn.com/schema/registry.json",
      name: "house-frontend-blocks",
      homepage: "https://example.com/house-frontend-blocks",
      items: registryItems,
    },
    null,
    2
  ) + "\n"
);

writeFileSync(
  join(registryDir, "README.md"),
  `# House Frontend Blocks

Open-source, source-owned starter blocks for common product surfaces.

These blocks are intentionally backend-agnostic. Wire auth to Clerk, billing to your provider, chat to your backend, and maps to MapLibre/data APIs after the UI shell is in place.

Generated blocks:

${blocks.map((item) => `- ${item.name}: ${item.description}`).join("\n")}
`
);

console.log(`Created ${registryPath}`);
console.log(`Created ${blocks.length} usable block templates under ${registryDir}`);
console.log("Next: review the generated blocks, wire domain data, and validate with shadcn registry tooling.");
