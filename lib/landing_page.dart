import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

class LoginPage extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onLogin;
  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  void _handleLogin() async {
    final usernameQuery = _usernameController.text.trim();
    final password = _passwordController.text;
    if (usernameQuery.isEmpty || password.isEmpty) return;
    
    setState(() { _isLoading = true; _errorMessage = null; });
    
    // 1. Authenticate with Supabase
    final foundUser = await SupabaseService.authenticate(usernameQuery);
    
    if (foundUser == null || foundUser['password'] != password) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Invalid username or password.'; });
      return;
    }
    
    if (foundUser['is_active'] == false) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'This account has been disabled.'; });
      return;
    }
    
    // 2. Refresh app data on successful login
    await SupabaseService.pullFromCloud();

    if (!mounted) return;
    setState(() => _isLoading = false);
    widget.onLogin(foundUser);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
      body: Row(children: [
        // Left brand panel with ultra-safe premium gradient
        Expanded(
          flex: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image (Premium Roastery)
              Image.asset(
                'assets/coffee_roastery_bg.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1C1008)),
              ),
              // Espresso Gradient Overlay (Immersion)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      Color(0xFF0F0804), // Dark espresso
                      Color(0xCC2D1B0E), // Roasted bean (70% opacity)
                      Color(0x991C1008), // Coffee black (60% opacity)
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
              ),
              // Content (Logo + Brand Text)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Image.asset(
                      'assets/logo_master.png',
                      width: 140,
                      cacheWidth: 280, // High-DPI optimization
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.coffee_rounded, size: 80, color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Innovative Cuppa',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    child: Text(
                      'INVENTORY MANAGEMENT SYSTEM',
                      style: TextStyle(
                        color: Color(0xFFC8822A),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 100),
                  Text(
                    '© 2026 Innovative Cuppa Co.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Right login form - animations removed for stability
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1008),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 48),
                    _fieldLabel('USERNAME'),
                    const SizedBox(height: 10),
                    _inputField(
                      controller: _usernameController,
                      focusNode: _usernameFocusNode,
                      hint: 'Enter your username',
                      icon: Icons.person_outline_rounded,
                      autofocus: true,
                      onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 24),
                    _fieldLabel('PASSWORD'),
                    const SizedBox(height: 10),
                    _inputField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePassword,
                      onSubmitted: (_) => _handleLogin(),
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    if (_errorMessage != null) 
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1008),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black38, letterSpacing: 1.0),
  );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focusNode,
    bool autofocus = false,
    bool obscure = false,
    void Function(String)? onSubmitted,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8E4DF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE8E4DF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC8822A), width: 2)),
      ),
    );
  }
}
