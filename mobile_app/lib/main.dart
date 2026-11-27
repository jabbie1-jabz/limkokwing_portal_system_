import 'package:flutter/material.dart';

import 'portal_api.dart';

const requestCategories = [
  'IT & Digital Services',
  'Housing & Utilities',
  'Transportation',
  'Health & Wellness',
  'Education & Training',
  'Finance & Billing',
  'Safety & Community',
  'Other',
];

const serviceTypes = [
  'Technical issue',
  'Account or login problem',
  'Service request',
  'Complaint or feedback',
  'Maintenance or repair request',
  'Information or guidance needed',
  'Billing or payment issue',
  'Safety or community concern',
  'Other request',
];

const requestStatuses = ['Pending', 'In Progress', 'Approved', 'Resolved'];
const requestPriorities = ['Low', 'Normal', 'High'];

void main() {
  runApp(const LimkokwingCampusPortalApp());
}

class LimkokwingCampusPortalApp extends StatefulWidget {
  const LimkokwingCampusPortalApp({super.key});

  @override
  State<LimkokwingCampusPortalApp> createState() =>
      _LimkokwingCampusPortalAppState();
}

class _LimkokwingCampusPortalAppState extends State<LimkokwingCampusPortalApp> {
  final _api = PortalApi();
  Map<String, dynamic>? _user;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Limkokwing Campus Portal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4B1D78)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: _user == null
          ? SignInScreen(
              api: _api,
              onSignedIn: (user) => setState(() => _user = user),
            )
          : PortalHomeScreen(
              api: _api,
              user: _user!,
              onSignedOut: () => setState(() => _user = null),
            ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.api, required this.onSignedIn, super.key});

  final PortalApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _campusId = TextEditingController();
  final _campusCode = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  var _obscurePassword = true;

  @override
  void dispose() {
    _campusId.dispose();
    _campusCode.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await widget.api.login(
        email: _email.text.trim(),
        password: _password.text,
        campusId: _campusId.text.trim(),
        campusCode: _campusCode.text.trim(),
      );
      if (mounted) widget.onSignedIn(user);
    } on PortalApiException catch (error) {
      if (!mounted) return;
      _showMessage(context, error.message);
    } on FormatException catch (error) {
      if (!mounted) return;
      _showMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      _showMessage(context, 'Could not connect to the campus portal.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.account_balance,
                      size: 58,
                      color: Color(0xFF4B1D78),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Limkokwing Campus Portal',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to manage your campus service requests.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _campusId,
                      decoration: const InputDecoration(
                        labelText: 'Campus ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _campusCode,
                      decoration: const InputDecoration(
                        labelText: 'Campus code',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your password.'
                          : null,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Students need their campus ID and code. Administrators may leave those fields blank.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => RegisterScreen(api: widget.api),
                              ),
                            ),
                      child: const Text('Create a student account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.api, super.key});

  final PortalApi api;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _campusId = TextEditingController();
  final _campusCode = TextEditingController();
  final _studentId = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _campusId.dispose();
    _campusCode.dispose();
    _studentId.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final message = await widget.api.register(
        fullName: _fullName.text.trim(),
        campusId: _campusId.text.trim(),
        campusCode: _campusCode.text.trim(),
        studentId: _studentId.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } on PortalApiException catch (error) {
      _showMessage(context, error.message);
    } on Exception {
      _showMessage(context, 'Could not create your account.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create student account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'A campus administrator must verify your student ID before you can sign in.',
                    ),
                    const SizedBox(height: 16),
                    _input(_fullName, 'Full name'),
                    _input(
                      _campusId,
                      'Campus ID',
                      keyboardType: TextInputType.number,
                    ),
                    _input(
                      _campusCode,
                      'Campus code',
                      obscureText: true,
                      keyboardType: TextInputType.number,
                    ),
                    _input(_studentId, 'Student ID'),
                    _input(
                      _email,
                      'Email address',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    _input(
                      _password,
                      'Password (at least 8 characters)',
                      obscureText: true,
                      validator: (value) => value == null || value.length < 8
                          ? 'Password must be at least 8 characters.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _register,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _input(
  TextEditingController controller,
  String label, {
  TextInputType? keyboardType,
  bool obscureText = false,
  String? Function(String?)? validator,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator:
          validator ??
          (value) => value == null || value.trim().isEmpty
              ? 'This field is required.'
              : null,
    ),
  );
}

class PortalHomeScreen extends StatefulWidget {
  const PortalHomeScreen({
    required this.api,
    required this.user,
    required this.onSignedOut,
    super.key,
  });

  final PortalApi api;
  final Map<String, dynamic> user;
  final VoidCallback onSignedOut;

  @override
  State<PortalHomeScreen> createState() => _PortalHomeScreenState();
}

class _PortalHomeScreenState extends State<PortalHomeScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic> _stats = {};
  var _busy = true;
  var _selectedTab = 0;
  String? _error;

  bool get _isAdmin => widget.user['role'] == 'admin';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.loadRequests();
      if (!mounted) return;
      setState(() {
        _requests = (result['requests'] as List).cast<Map<String, dynamic>>();
        _stats = result['stats'] as Map<String, dynamic>;
        _busy = false;
      });
    } on PortalApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load campus requests.';
        _busy = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.logout();
    } on Exception {
      if (mounted) {
        _showMessage(context, 'Could not contact the server to sign out.');
      }
    } finally {
      widget.onSignedOut();
    }
  }

  Future<void> _openNewRequest() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NewRequestScreen(api: widget.api),
      ),
    );
    if (created == true) {
      await _loadRequests();
    }
  }

  Future<void> _openRequest(Map<String, dynamic> request) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RequestDetailsScreen(
          api: widget.api,
          requestId: request['id'] as int,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final showUsers = _isAdmin && _selectedTab == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Portal'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: showUsers
          ? AdminUsersScreen(api: widget.api)
          : _buildRequests(context),
      floatingActionButton: !_isAdmin && !showUsers
          ? FloatingActionButton.extended(
              onPressed: _openNewRequest,
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            )
          : null,
      bottomNavigationBar: _isAdmin
          ? NavigationBar(
              selectedIndex: _selectedTab,
              onDestinationSelected: (index) {
                setState(() => _selectedTab = index);
                if (index == 0) _loadRequests();
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: 'Requests',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: 'Students',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildRequests(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(
            'Welcome, ${widget.user['full_name']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(_isAdmin ? 'Administrator' : 'Your campus service requests'),
          if (_isAdmin) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in requestStatuses)
                  _StatCard(label: status, value: '${_stats[status] ?? 0}'),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            _isAdmin ? 'All requests' : 'My requests',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _ErrorPanel(message: _error!, onRetry: _loadRequests)
          else if (_requests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: Text('No service requests yet.')),
            )
          else
            for (final request in _requests)
              _RequestCard(
                request: request,
                isAdmin: _isAdmin,
                onTap: () => _openRequest(request),
              ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isAdmin,
    required this.onTap,
  });

  final Map<String, dynamic> request;
  final bool isAdmin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          '${request['ticket_code']} · ${request['category']}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [
              request['service_type'] as String,
              if (isAdmin) request['full_name'] as String? ?? '',
              'Priority: ${request['priority']}',
            ].where((value) => value.isNotEmpty).join('\n'),
          ),
        ),
        trailing: _StatusChip(status: request['status'] as String),
        isThreeLine: isAdmin,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Resolved' => Colors.green,
      'Approved' => Colors.blue,
      'In Progress' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Chip(
      label: Text(status),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({required this.api, super.key});

  final PortalApi api;

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  String? _category;
  String? _serviceType;
  String _priority = 'Normal';
  var _busy = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.api.createRequest(
        category: _category!,
        serviceType: _serviceType!,
        description: _description.text.trim(),
        priority: _priority,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PortalApiException catch (error) {
      if (!mounted) return;
      _showMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      _showMessage(context, 'Could not submit the request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New service request')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Tell us what you need help with so we can route your request.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: requestCategories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value),
                validator: (value) =>
                    value == null ? 'Select a category.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _serviceType,
                decoration: const InputDecoration(labelText: 'Service type'),
                items: serviceTypes
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _serviceType = value),
                validator: (value) =>
                    value == null ? 'Select a service type.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: requestPriorities
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue',
                  alignLabelWithHint: true,
                ),
                minLines: 5,
                maxLines: 8,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Describe your request.'
                    : null,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const CircularProgressIndicator()
                    : const Text('Submit request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RequestDetailsScreen extends StatefulWidget {
  const RequestDetailsScreen({
    required this.api,
    required this.requestId,
    required this.isAdmin,
    super.key,
  });

  final PortalApi api;
  final int requestId;
  final bool isAdmin;

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  late Future<Map<String, dynamic>> _details;

  @override
  void initState() {
    super.initState();
    _details = widget.api.loadRequest(widget.requestId);
  }

  void _reload() => setState(() {
    _details = widget.api.loadRequest(widget.requestId);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request details')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorPanel(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final item = snapshot.data!['request'] as Map<String, dynamic>;
          final notes = (snapshot.data!['notes'] as List)
              .cast<Map<String, dynamic>>();
          return _RequestDetailsBody(
            api: widget.api,
            item: item,
            notes: notes,
            isAdmin: widget.isAdmin,
            onUpdated: _reload,
          );
        },
      ),
    );
  }
}

class _RequestDetailsBody extends StatefulWidget {
  const _RequestDetailsBody({
    required this.api,
    required this.item,
    required this.notes,
    required this.isAdmin,
    required this.onUpdated,
  });

  final PortalApi api;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> notes;
  final bool isAdmin;
  final VoidCallback onUpdated;

  @override
  State<_RequestDetailsBody> createState() => _RequestDetailsBodyState();
}

class _RequestDetailsBodyState extends State<_RequestDetailsBody> {
  late String _status = widget.item['status'] as String;
  late String _priority = widget.item['priority'] as String;
  final _note = TextEditingController();
  var _isInternal = false;
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      await widget.api.updateRequest(
        id: widget.item['id'] as int,
        status: _status,
        priority: _priority,
        note: _note.text.trim(),
        isInternal: _isInternal,
      );
      if (!mounted) return;
      _note.clear();
      _showMessage(context, 'Request updated.');
      widget.onUpdated();
    } on PortalApiException catch (error) {
      if (!mounted) return;
      _showMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      _showMessage(context, 'Could not update the request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          item['ticket_code'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _StatusChip(status: item['status'] as String),
        const SizedBox(height: 16),
        _DetailLine(label: 'Category', value: item['category'] as String),
        _DetailLine(
          label: 'Service type',
          value: item['service_type'] as String,
        ),
        _DetailLine(label: 'Priority', value: item['priority'] as String),
        _DetailLine(label: 'Description', value: item['description'] as String),
        if (widget.isAdmin) ...[
          _DetailLine(label: 'Student', value: item['full_name'] as String),
          _DetailLine(
            label: 'Student ID',
            value: item['student_id'] as String? ?? '',
          ),
          _DetailLine(label: 'Email', value: item['email'] as String),
        ],
        const SizedBox(height: 18),
        Text('Updates', style: Theme.of(context).textTheme.titleLarge),
        if (widget.notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No updates yet.'),
          )
        else
          for (final note in widget.notes)
            Card(
              child: ListTile(
                title: Text(note['note'] as String),
                subtitle: Text(
                  '${note['full_name']} · ${note['created_at']}'
                  '${widget.isAdmin && note['is_internal'] == 1 ? ' · Internal' : ''}',
                ),
              ),
            ),
        if (widget.isAdmin) ...[
          const Divider(height: 32),
          Text('Update request', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: requestStatuses
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: requestPriorities
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Add an update',
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 4,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Internal note (hidden from student)'),
            value: _isInternal,
            onChanged: (value) => setState(() => _isInternal = value),
          ),
          FilledButton(
            onPressed: _busy ? null : _update,
            child: _busy
                ? const CircularProgressIndicator()
                : const Text('Save update'),
          ),
        ],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({required this.api, super.key});

  final PortalApi api;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _users = widget.api.loadUsers();
  }

  void _reload() => setState(() => _users = widget.api.loadUsers());

  Future<void> _verify(int userId) async {
    try {
      await widget.api.verifyStudent(userId);
      if (mounted) _showMessage(context, 'Student identity verified.');
      _reload();
    } on PortalApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    } on Exception {
      if (mounted) _showMessage(context, 'Could not verify the student.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorPanel(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }
        final users = snapshot.data!
            .where((user) => user['role'] == 'user')
            .toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Student accounts',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No student accounts found.')),
                ),
              for (final user in users)
                Card(
                  child: ListTile(
                    title: Text(user['full_name'] as String),
                    subtitle: Text(
                      '${user['student_id'] ?? 'No student ID'}\n'
                      '${user['email']}\n'
                      'Identity: ${user['identity_status']}',
                    ),
                    isThreeLine: true,
                    trailing: user['identity_status'] == 'pending'
                        ? IconButton(
                            tooltip: 'Verify student',
                            onPressed: () => _verify(user['id'] as int),
                            icon: const Icon(Icons.verified_outlined),
                          )
                        : const Icon(Icons.verified, color: Colors.green),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.wifi_off, size: 42),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
