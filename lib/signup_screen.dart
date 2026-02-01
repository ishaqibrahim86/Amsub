import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final referralController = TextEditingController();
  final passwordController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode(); // 👈 fix for Flutter web error

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameFocus.requestFocus(); // 👈 safely apply focus
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final url = Uri.parse('https://amsubnig.com/rest-auth/registration/');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "username": usernameController.text.trim(),
          "email": emailController.text.trim(),
          "password1": passwordController.text,
          "password2": passwordController.text,
          "Phone": phoneController.text.trim(),
          "FullName": fullNameController.text.trim(),
          "Address": addressController.text.trim(),
          "referer_username": referralController.text.trim(),
        }),
      );

      print('Response code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful!')),
        );
        Navigator.pop(context); // Back to login
      } else {
        final decoded = jsonDecode(response.body);
        setState(() {
          errorMessage = decoded.values.first.first;
        });
      }
    } catch (e) {
      print('Exception during registration: $e');
      setState(() {
        errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _textField(TextEditingController controller, String label,
      {bool isPassword = false,
        TextInputType inputType = TextInputType.text,
        FocusNode? focusNode}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword,
        keyboardType: inputType,
        validator: (value) =>
        (value == null || value.isEmpty) && !label.contains('[Optional]')
            ? 'Please enter $label'
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: isPassword ? const Icon(Icons.visibility_off) : null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _textField(fullNameController, 'Full Name'),
              _textField(usernameController, 'Username', focusNode: _usernameFocus),
              _textField(emailController, 'Email Address', inputType: TextInputType.emailAddress),
              _textField(phoneController, 'Phone Number', inputType: TextInputType.phone),
              _textField(addressController, 'House Address'),
              _textField(referralController, 'Referral username [Optional]'),
              _textField(passwordController, 'Password', isPassword: true),
              const SizedBox(height: 16),
              if (errorMessage != null)
                Text(errorMessage!, style: const TextStyle(color: Colors.red)),
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _register,
                child: const Text('Sign Up'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("I'm already a member. Sign In"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
