// lib/core/config.dart

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qvbojzmtdbrrahtewrrr.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_DaWE6HlrHwmTJAMeWOIyEQ_xOih2tAG',
);