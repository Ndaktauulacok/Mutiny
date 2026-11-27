import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/cloud_sync.dart';
import '../../services/library_store.dart';
import '../glass.dart';
import '../theme.dart';

/// Sign in / create account, or (when signed in) sync status + sign out.
void showAccountSheet(BuildContext context) {
  showGlassSheet(context, builder: (_) => const _AccountView());
}

class _AccountView extends StatelessWidget {
  const _AccountView();

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    return cloud.signedIn ? const _SignedIn() : const _AuthForm();
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn();

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final (icon, title, color) = switch (cloud.status) {
      SyncStatus.syncing => (Icons.sync_rounded, 'Syncing…', MColors.lavender),
      SyncStatus.offline => (Icons.cloud_off_rounded, 'Waiting for internet', const Color(0xFFFFB86B)),
      _ => (Icons.cloud_done_rounded, 'All synced', const Color(0xFF7CF5C9)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: color),
          const SizedBox(height: 10),
          Text(title, style: MText.h2),
          const SizedBox(height: 4),
          Text(cloud.email ?? '', style: MText.body),
          if (cloud.lastSync != null) ...[
            const SizedBox(height: 4),
            Text('Last sync ${TimeOfDay.fromDateTime(cloud.lastSync!).format(context)}', style: MText.caption),
          ],
          if (cloud.pendingDownloads > 0) ...[
            const SizedBox(height: 4),
            Text('Downloading ${cloud.pendingDownloads} file(s)…', style: MText.caption),
          ],
          if (cloud.error != null) ...[
            const SizedBox(height: 8),
            Text(cloud.error!, style: MText.caption.copyWith(color: const Color(0xFFFFB86B)), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          const Text(
            'Your playlists, likes, followed artists, stations, profile and your own songs '
            'are the same on every phone, tablet and computer where you sign in.',
            style: MText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PillButton(label: 'Sync now', icon: Icons.sync_rounded, onTap: () => cloud.fullSync()),
              const SizedBox(width: 10),
              PillButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                onTap: () async {
                  await cloud.signOut();
                  if (context.mounted) {
                    Navigator.pop(context);
                    toast(context, 'Signed out. Your music stays on this device.');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatefulWidget {
  const _AuthForm();

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  bool _signUp = false;
  bool _busy = false;
  bool _hide = true;
  String? _message;
  bool _messageIsError = true;
  late final _name = TextEditingController(text: context.read<LibraryStore>().profile.name == 'Listener' ? '' : context.read<LibraryStore>().profile.name);
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cloud = context.read<CloudSync>();
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 6) {
      setState(() {
        _message = 'Enter your email and a password of at least 6 characters.';
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final msg = _signUp
        ? await cloud.signUp(email: email, password: _password.text, name: _name.text)
        : await cloud.signIn(email: email, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (msg == null) {
      Navigator.pop(context);
      toast(context, _signUp ? 'Account created. Your music now syncs.' : 'Signed in. Syncing your music…');
    } else {
      setState(() {
        _message = msg;
        _messageIsError = !msg.startsWith('Almost done');
      });
    }
  }

  Future<void> _forgot() async {
    if (!_email.text.contains('@')) {
      setState(() {
        _message = 'Type your email first, then tap Forgot password.';
        _messageIsError = true;
      });
      return;
    }
    final msg = await context.read<CloudSync>().resetPassword(_email.text);
    if (mounted) {
      setState(() {
        _message = msg;
        _messageIsError = false;
      });
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: MColors.textTertiary),
        prefixIcon: Icon(icon, color: MColors.lavender, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MColors.glassBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MColors.lavender),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 16, color: MColors.text, fontWeight: FontWeight.w500);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.devices_rounded, size: 40, color: MColors.lavender),
          const SizedBox(height: 10),
          Text(_signUp ? 'Create your Mutiny account' : 'Sign in to Mutiny', style: MText.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          const Text(
            'One account on your phone, tablet and computer: playlists, likes and your songs everywhere.',
            style: MText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_signUp) ...[
            TextField(controller: _name, style: style, textInputAction: TextInputAction.next, decoration: _dec('Your name', Icons.person_rounded)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _email,
            style: style,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: _dec('Email', Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            style: style,
            obscureText: _hide,
            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: _dec(
              'Password',
              Icons.lock_rounded,
              suffix: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: MColors.textTertiary),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: MText.body.copyWith(color: _messageIsError ? const Color(0xFFFF8FA3) : const Color(0xFF7CF5C9)),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: _busy
                ? const SizedBox.square(dimension: 30, child: CircularProgressIndicator(strokeWidth: 2.5))
                : PillButton(
                    label: _signUp ? 'Create account' : 'Sign in',
                    icon: _signUp ? Icons.person_add_rounded : Icons.login_rounded,
                    filled: true,
                    onTap: _submit,
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _signUp = !_signUp;
                  _message = null;
                }),
                child: Text(
                  _signUp ? 'I have an account' : 'Create an account',
                  style: const TextStyle(color: MColors.lavender, fontWeight: FontWeight.w700),
                ),
              ),
              if (!_signUp)
                TextButton(
                  onPressed: _forgot,
                  child: const Text('Forgot password?', style: TextStyle(color: MColors.textSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small cloud icon that shows the sync state; tap for the account sheet.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final (icon, color) = switch (cloud.status) {
      SyncStatus.signedOut => (Icons.cloud_outlined, MColors.textSecondary),
      SyncStatus.syncing => (Icons.cloud_sync_rounded, MColors.lavender),
      SyncStatus.offline => (Icons.cloud_off_rounded, const Color(0xFFFFB86B)),
      SyncStatus.synced => (Icons.cloud_done_rounded, const Color(0xFF7CF5C9)),
    };
    return GlassIconButton(icon: icon, color: color, iconSize: 20, tooltip: 'Account & sync', onTap: () => showAccountSheet(context));
  }
}

/// Card inviting the user to sign in (Library / Profile).
class SignInCard extends StatelessWidget {
  const SignInCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    if (cloud.signedIn) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Pressable(
        onTap: () => showAccountSheet(context),
        child: Glass(
          radius: 20,
          tint: const Color(0xFFE879F9),
          strength: 1.4,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFF0ABFC), Color(0xFF8B5CF6)]),
                ),
                child: const Icon(Icons.devices_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Use Mutiny on all your devices', style: MText.title),
                    SizedBox(height: 2),
                    Text('Sign in to sync playlists and songs', style: MText.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: MColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
