-- Issue Management System Database Schema for Supabase

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (managed by Supabase Auth, but we extend it here)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE,
  full_name TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'user' CHECK (role IN ('admin', 'user')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL
);

-- Categories table
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  color TEXT DEFAULT '#6366f1',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- Tags table
CREATE TABLE IF NOT EXISTS public.tags (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  color TEXT DEFAULT '#8b5cf6',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL
);

-- Issues table
CREATE TABLE IF NOT EXISTS public.issues (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  due_date TIMESTAMP WITH TIME ZONE,
  resolved_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL
);

-- Issue-Tags junction table (many-to-many)
CREATE TABLE IF NOT EXISTS public.issue_tags (
  issue_id UUID REFERENCES public.issues(id) ON DELETE CASCADE,
  tag_id UUID REFERENCES public.tags(id) ON DELETE CASCADE,
  PRIMARY KEY (issue_id, tag_id)
);

-- Comments table
CREATE TABLE IF NOT EXISTS public.comments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  issue_id UUID NOT NULL REFERENCES public.issues(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL
);

-- Issue History table (for tracking changes)
CREATE TABLE IF NOT EXISTS public.issue_history (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  issue_id UUID NOT NULL REFERENCES public.issues(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()) NOT NULL
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_issues_status ON public.issues(status);
CREATE INDEX IF NOT EXISTS idx_issues_category ON public.issues(category_id);
CREATE INDEX IF NOT EXISTS idx_issues_assignee ON public.issues(assignee_id);
CREATE INDEX IF NOT EXISTS idx_issues_reporter ON public.issues(reporter_id);
CREATE INDEX IF NOT EXISTS idx_comments_issue ON public.comments(issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_history_issue ON public.issue_history(issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_tags_issue ON public.issue_tags(issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_tags_tag ON public.issue_tags(tag_id);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issue_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issue_tags ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Public profiles are viewable by everyone"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- RLS Policies for categories
CREATE POLICY "Categories are viewable by everyone"
  ON public.categories FOR SELECT
  USING (true);

CREATE POLICY "Authenticated users can create categories"
  ON public.categories FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can update categories"
  ON public.categories FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- RLS Policies for tags
CREATE POLICY "Tags are viewable by everyone"
  ON public.tags FOR SELECT
  USING (true);

CREATE POLICY "Authenticated users can create tags"
  ON public.tags FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- RLS Policies for issues
CREATE POLICY "Issues are viewable by authenticated users"
  ON public.issues FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can create issues"
  ON public.issues FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "Users can update issues they created or are assigned to"
  ON public.issues FOR UPDATE
  USING (
    auth.uid() = reporter_id OR
    auth.uid() = assignee_id OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Users can delete issues they created"
  ON public.issues FOR DELETE
  USING (
    auth.uid() = reporter_id OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- RLS Policies for comments
CREATE POLICY "Comments are viewable by authenticated users"
  ON public.comments FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can create comments"
  ON public.comments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own comments"
  ON public.comments FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own comments"
  ON public.comments FOR DELETE
  USING (
    auth.uid() = user_id OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- RLS Policies for issue_history
CREATE POLICY "Issue history is viewable by authenticated users"
  ON public.issue_history FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- RLS Policies for issue_tags
CREATE POLICY "Issue tags are viewable by everyone"
  ON public.issue_tags FOR SELECT
  USING (true);

CREATE POLICY "Users can add tags to issues they can update"
  ON public.issue_tags FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.issues
      WHERE issues.id = issue_id
      AND (issues.reporter_id = auth.uid() OR issues.assignee_id = auth.uid())
    )
  );

-- Function to automatically create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, username)
  VALUES (
    new.id,
    new.email,
    split_part(new.email, '@', 1)
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = TIMEZONE('utc', NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_issues_updated_at BEFORE UPDATE ON public.issues
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_comments_updated_at BEFORE UPDATE ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Insert default categories and tags
INSERT INTO public.categories (name, description, color) VALUES
  ('Bug', 'Software defects and errors', '#ef4444'),
  ('Feature Request', 'New feature proposals', '#3b82f6'),
  ('Improvement', 'Enhancements to existing features', '#22c55e'),
  ('Documentation', 'Documentation issues', '#f59e0b'),
  ('Support', 'User support inquiries', '#8b5cf6')
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.tags (name, color) VALUES
  ('urgent', '#ef4444'),
  ('help-wanted', '#f59e0b'),
  ('good-first-issue', '#22c55e'),
  ('enhancement', '#3b82f6'),
  ('documentation', '#8b5cf6'),
  ('bug', '#ef4444'),
  ('question', '#06b6d4')
ON CONFLICT (name) DO NOTHING;
