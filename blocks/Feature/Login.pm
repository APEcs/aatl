## @file
# This file contains the implementation of the login/logout facility.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
package Feature::Login;

## @class Feature::Login
# A 'stand alone' login implementation. This presents the user with a
# login form, checks the credentials they enter, and then redirects
# them back to the task they were performing that required a login.
#
# @todo Account recovery (complicated by auth backend!)
# @todo Activation resend
#
use strict;
use base qw(Feature); # This class extends Feature
use Utils qw(path_join);
use Data::Dumper;

# ============================================================================
#  Emailer functions

## @method $ send_reg_email($user, $password)
# Send a registration welcome message to the specified user. This send an email
# to the user including their username, password, and a link to the activation
# page for their account.
#
# @param user     A reference to a user record hash.
# @param password The unencrypted version of the password set for the user.
# @return undef on success, otherwise an error message.
sub send_reg_email {
    my $self     = shift;
    my $user     = shift;
    my $password = shift;

    my $url = $self -> build_url("fullurl"  => 1,
                                 "block"    => "login",
                                 "paramstr" => "actcode=".$user -> {"act_code"});

    return $self -> {"template"} -> email_template("feature/login/email_registered.tem",
                                                   {"***from***"     => $self -> {"settings"} -> {"config"} -> {"Core:admin_email"},
                                                    "***to***"       => $user -> {"email"},
                                                    "***subject***"  => $self -> {"template"} -> replace_langvar("LOGIN_REG_SUBJECT"),
                                                    "***username***" => $user -> {"username"},
                                                    "***password***" => $password,
                                                    "***act_code***" => $user -> {"act_code"},
                                                    "***act_url***"  => $url,
                                                   });
}


# ============================================================================
#  Validation functions

## @method private @ validate_login()
# Determine whether the username and password provided by the user are valid. If
# they are, return the user's data.
#
# @return An array of two values: A reference to the user's data on success,
#         or an error string if the login failed, and a reference to a hash of
#         arguments that passed validation.
sub validate_login {
    my $self   = shift;
    my $error  = "";
    my $args   = {};

    my $errtem = $self -> {"template"} -> load_template("feature/login/error.tem");

    # Check that the username is provided and valid
    ($args -> {"username"}, $error) = $self -> validate_string("username", {"required"   => 1,
                                                                            "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_USERNAME"),
                                                                            "minlen"     => 2,
                                                                            "maxlen"     => 32,
                                                                            "formattest" => '^[-\w]+$',
                                                                            "formatdesc" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADUSERCHAR")});
    # Bomb out at this point if the username is not valid.
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $error}), $args)
        if($error);

    # Do the same with the password...
    ($args -> {"password"}, $error) = $self -> validate_string("password", {"required"   => 1,
                                                                            "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_PASSWORD"),
                                                                            "minlen"     => 2,
                                                                            "maxlen"     => 255});
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $error}), $args)
        if($error);

    # Username and password appear to be present and contain sane characters. Try to log the user in...
    my $user = $self -> {"session"} -> {"auth"} -> valid_user($args -> {"username"}, $args -> {"password"});

    # If the user is valid, is the account active?
    if($user) {
        # If the account is active, the user is good to go
        if($user -> {"activated"}) {
            return ($user, $args);
        } else {
            # Otherwise, send back the 'account needs activating' error
            return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_INACTIVE")}), $args);
        }
    }

    # User is valid!
    return ($user, $args) if($user);

    # User is not valid, does the auth's errstr contain anything?
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"session"} -> auth_error()}), $args)
        if($self -> {"session"} -> auth_error());

    # Nothing useful, just return a fallback
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_INVALID")}), $args);
}


## @method private @ validate_register()
# Determine whether the username, email, and security question provided by the user
# are valid. If they are, return true.
#
# @return The new user's record on success, an error string if the register failed.
sub validate_register {
    my $self   = shift;
    my $error  = "";
    my $errors = "";
    my $args   = {};

    my $errtem = $self -> {"template"} -> load_template("feature/login/reg_error.tem");

    # User attempted self-register when it is disabled? Naughty user, no cookie!
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_NOSELFREG")}), $args)
        unless($self -> {"settings"} -> {"config"} -> {"Feature::Login:allow_self_register"});

    # Check that the username is provided and valid
    ($args -> {"regname"}, $error) = $self -> validate_string("regname", {"required"   => 1,
                                                                          "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_USERNAME"),
                                                                          "minlen"     => 2,
                                                                          "maxlen"     => 32,
                                                                          "formattest" => '^[-\w]+$',
                                                                          "formatdesc" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADUSERCHAR")
                                                              });
    # Is the username valid?
    if($error) {
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $error});
    } else {
        # Is the username in use?
        my $user = $self -> {"session"} -> get_user($args -> {"regname"});
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_USERINUSE")})
            if($user);
    }

    # And the email
    ($args -> {"email"}, $error) = $self -> validate_string("email", {"required"   => 1,
                                                                      "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_EMAIL"),
                                                                      "minlen"     => 2,
                                                                      "maxlen"     => 256
                                                            });
    if($error) {
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $error});
    } else {

        # Check that the address is structured in a vaguely valid way
        # Yes, this is not fully RFC compliant, but frankly going down that road invites a
        # level of utter madness that would make Azathoth himself utter "I say, steady on now..."
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADEMAIL")})
            if($args -> {"email"} !~ /^[\w.+-]+\@([\w-]+\.)+\w+$/);

        # Is the email address in use?
        my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> get_user_byemail($args -> {"email"});
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_EMAILINUSE")})
            if($user);
    }

    # Did the user get the 'Are you a human' question right?
    ($args -> {"answer"}, $error) = $self -> validate_string("answer", {"required"   => 1,
                                                                        "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_SECURITY"),
                                                                        "minlen"     => 2,
                                                                        "maxlen"     => 255,
                                                             });
    if($error) {
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $error});
    } else {
        $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADSECURE")})
            unless(lc($args -> {"answer"}) eq lc($self -> {"settings"} -> {"config"} -> {"Feature::Login:self_register_answer"}));
    }

    # Halt here if there are any problems.
    return ($self -> {"template"} -> load_template("feature/login/reg_errorlist.tem", {"***errors***" => $errors}), $args)
        if($errors);

    # Get here an the user's details are okay, register the new user.
    my ($user, $password) = $self -> {"session"} -> {"auth"} -> {"app"} -> create_user($args -> {"regname"}, $args -> {"email"});
    $errors .= $self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"session"} -> {"auth"} -> {"app"} -> {"errstr"}})
        if(!ref($user));

    # Send registration email
    my $err = $self -> send_reg_email($user, $password);
    return ($err, $args) if($err);

    # User is registered...
    return ($user, $args);
}


## @method private @ validate_actcode()
# Determine whether the activation code provided by the user is valid
#
# @return An array of two values: the first is a reference to the activated
#         user's data hash on success, an error message otherwise; the
#         second is the args parsed from the activation data.
sub validate_actcode {
    my $self = shift;
    my $args = {};
    my $error;

    my $errtem = $self -> {"template"} -> load_template("feature/login/act_error.tem");

    # Check that the code has been provided and contains allowed characters
    ($args -> {"actcode"}, $error) = $self -> validate_string("actcode", {"required"   => 1,
                                                                          "nicename"   => $self -> {"template"} -> replace_langvar("LOGIN_ACTCODE"),
                                                                          "minlen"     => 64,
                                                                          "maxlen"     => 64,
                                                                          "formattest" => '^[a-zA-Z0-9]+$',
                                                                          "formatdesc" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADACTCHAR")});
    # Bomb out at this point if the code is not valid.
    return $self -> {"template"} -> process_template($errtem, {"***reason***" => $error})
        if($error);

    my $user = $self -> {"session"} -> {"auth"} -> {"app"} -> activate_user($args -> {"actcode"});

    # Act code is valid, can a user be activated?
    return ($self -> {"template"} -> process_template($errtem, {"***reason***" => $self -> {"template"} -> replace_langvar("LOGIN_ERR_BADCODE")}), $args)
        unless($user);

    # User is active
    return ($user, $args);
}


# ============================================================================
#  Content generation functions

## @method private $ generate_login_form($error, $args)
# Generate the content of the login form.
#
# @param error A string containing errors related to logging in, or undef.
# @param args  A reference to a hash of intiial values.
# @return An array of two values: the page title, and a string containing
#         the login form.
sub generate_login_form {
    my $self  = shift;
    my $error = shift;
    my $args  = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("feature/login/error_box.tem", {"***message***" => $error})
        if($error);

    # Persist length is always in seconds, so convert it to something more readable
    my $persist_length = $self -> {"template"} -> humanise_seconds($self -> {"session"} -> {"auth"} -> get_config("max_autologin_time"));

    # if self-registration is enabled, turn on the option
    my $self_register = $self -> {"settings"} -> {"config"} -> {"Feature::Login:allow_self_register"} ?
                            $self -> {"template"} -> load_template("feature/login/selfreg.tem") :
                            $self -> {"template"} -> load_template("feature/login/no_selfreg.tem");

    return ($self -> {"template"} -> replace_langvar("LOGIN_TITLE"),
            $self -> {"template"} -> load_template("feature/login/form.tem", {"***error***"      => $error,
                                                                              "***persistlen***" => $persist_length,
                                                                              "***selfreg***"    => $self_register,
                                                                              "***target***"     => $self -> build_url("block" => "login"),
                                                                              "***course***"     => $self -> {"cgi"} -> param("course") || "",
                                                                              "***question***"   => $self -> {"settings"} -> {"config"} -> {"Feature::Login:self_register_question"},
                                                                              "***username***"   => $args -> {"username"},
                                                                              "***regname***"    => $args -> {"regname"},
                                                                              "***email***"      => $args -> {"email"}}));
}



## @method private @ generate_actcode_form($error)
# Generate a form through which the user may specify an activation code.
#
# @param error A string containing errors related to activating, or undef.
# @return An array of two values: the page title string, the code form
sub generate_actcode_form {
    my $self  = shift;
    my $error = shift;

    # Wrap the error message in a message box if we have one.
    $error = $self -> {"template"} -> load_template("feature/login/error_box.tem", {"***message***" => $error})
        if($error);

    return ($self -> {"template"} -> replace_langvar("LOGIN_TITLE"),
            $self -> {"template"} -> load_template("feature/login/act_form.tem", {"***error***"  => $error,
                                                                                  "***target***" => $self -> build_url("block" => "login")}));
}


## @method private @ generate_loggedin()
# Generate the contents of a page telling the user that they have successfully logged in.
#
# @return An array of three values: the page title string, the 'logged in' message, and
#         a meta element to insert into the head element to redirect the user.
sub generate_loggedin {
    my $self = shift;

    my $url = $self -> build_return_url();

    my $warning = "";

    # The user validation might have thrown up warning, so check that.
    $warning = $self -> {"template"} -> load_template("feature/login/warning_box.tem", {"***message***" => $self -> {"session"} -> auth_error()})
        if($self -> {"session"} -> auth_error());

    my ($content, $extrahead);

    # If any warnings were encountered, send back a different logged-in page to avoid
    # confusing users.
    if(!$warning) {
        # Note that, while it would be nice to immediately redirect users at this point,
        $content = $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("LOGIN_DONETITLE"),
                                                        "security",
                                                        $self -> {"template"} -> replace_langvar("LOGIN_SUMMARY"),
                                                        $self -> {"template"} -> replace_langvar("LOGIN_LONGDESC", {"***url***" => $url}),
                                                        undef,
                                                        "logincore",
                                                        [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                           "colour"  => "blue",
                                                           "action"  => "location.href='$url'"} ]);
        $extrahead = $self -> {"template"} -> load_template("refreshmeta.tem", {"***url***" => $url});

    # Users who have encountered warnings during login always get a login confirmation page, as it has
    # to show them the warning message box.
    } else {
        my $message = $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("LOGIN_DONETITLE"),
                                                           "security",
                                                           $self -> {"template"} -> replace_langvar("LOGIN_SUMMARY"),
                                                           $self -> {"template"} -> replace_langvar("LOGIN_NOREDIRECT", {"***url***" => $url,
                                                                                                                         "***supportaddr***" => ""}),
                                                           undef,
                                                           "logincore",
                                                           [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='$url'"} ]);
        $content = $self -> {"template"} -> load_template("feature/login/login_warn.tem", {"***message***" => $message,
                                                                                           "***warning***" => $warning});
    }

    # return the title, content, and extraheader. If the warning is set, do not include an autoredirect.
    return ($self -> {"template"} -> replace_langvar("LOGIN_DONETITLE"),
            $content, "",

            $extrahead);
}


## @method private @ generate_registered()
# Generate the contents of a page telling the user that they have successfully created an
# inactive account.
#
# @return An array of two values: the page title string, the 'registered' message.
sub generate_registered {
    my $self = shift;

    my $url = $self -> build_url("block" => "login", "paramstr" => "activate=act");

    return ($self -> {"template"} -> replace_langvar("LOGIN_REG_DONETITLE"),
            $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("LOGIN_REG_DONETITLE"),
                                                 "security",
                                                 $self -> {"template"} -> replace_langvar("LOGIN_REG_SUMMARY"),
                                                 $self -> {"template"} -> replace_langvar("LOGIN_REG_LONGDESC"),
                                                 undef,
                                                 "logincore",
                                                 [ {"message" => $self -> {"template"} -> replace_langvar("LOGIN_ACTIVATE"),
                                                    "colour"  => "blue",
                                                    "action"  => "location.href='$url'"} ]));
}


## @method private @ generate_activated($user)
# Generate the contents of a page telling the user that they have successfully activated
# their account.
#
# @return An array of two values: the page title string, the 'activated' message.
sub generate_activated {
    my $self = shift;

    my $target = $self -> build_url("block" => "login");

    return ($self -> {"template"} -> replace_langvar("LOGIN_ACT_DONETITLE"),
            $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("LOGIN_ACT_DONETITLE"),
                                                 "security",
                                                 $self -> {"template"} -> replace_langvar("LOGIN_ACT_SUMMARY"),
                                                 $self -> {"template"} -> replace_langvar("LOGIN_ACT_LONGDESC",
                                                                                          {"***target***" => $target}),
                                                 undef,
                                                 "logincore",
                                                        [ {"message" => $self -> {"template"} -> replace_langvar("LOGIN_LOGIN"),
                                                           "colour"  => "blue",
                                                           "action"  => "location.href='$target'"} ]));
}


## @method private @ generate_loggedout()
# Generate the contents of a page telling the user that they have successfully logged out.
#
# @return An array of three values: the page title string, the 'logged out' message, and
#         a meta element to insert into the head element to redirect the user.
sub generate_loggedout {
    my $self = shift;

    # NOTE: This is called **after** the session is deleted, so savestate will be undef. This
    # means that the user will be returned to a default (the login form, usually).
    my $url = $self -> build_return_url();

    # return the title, content, and extraheader
    return ($self -> {"template"} -> replace_langvar("LOGOUT_TITLE"),
            $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("LOGOUT_TITLE"),
                                                 "security",
                                                 $self -> {"template"} -> replace_langvar("LOGOUT_SUMMARY"),
                                                 $self -> {"template"} -> replace_langvar("LOGOUT_LONGDESC", {"***url***" => $url}),
                                                 undef,
                                                 "logincore",
                                                 [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                    "colour"  => "blue",
                                                    "action"  => "location.href='$url'"} ]),
            $self -> {"template"} -> load_template("refreshmeta.tem", {"***url***" => $url}));
}


# ============================================================================
#  Interface functions

## @method $ page_display()
# Generate the page content for this module.
sub page_display {
    my $self = shift;

    # We need to determine what the page title should be, and the content to shove in it...
    my ($title, $body, $extrahead) = ("", "", "");

    # If the user is not anonymous, they have logged in already.
    if(!$self -> {"session"} -> anonymous_session()) {

        # Is the user requesting a logout? If so, doo eet.
        if(defined($self -> {"cgi"} -> param("logout"))) {
            $self -> log("logout", $self -> {"session"} -> get_session_userid());
            if($self -> {"session"} -> delete_session()) {
                ($title, $body, $extrahead) = $self -> generate_loggedout();
            } else {
                return $self -> generate_fatal($SessionHandler::errstr);
            }

        # Already logged in, huh. Send back the logged-in message to remind them...
        } else {
            ($title, $body, $extrahead) = $self -> generate_loggedin();
        }

    # User is anonymous - do we have a login?
    } elsif(defined($self -> {"cgi"} -> param("login"))) {

        # Validate the other fields...
        my ($user, $args) = $self -> validate_login();

        # Do we have any errors? If so, send back the login form with them
        if(!ref($user)) {
            $self -> log("login error", $user);
            ($title, $body) = $self -> generate_login_form($user, $args);

        # No errors, user is valid...
        } else {
            # create the new logged-in session, copying over the savestate session variable
            $self -> {"session"} -> create_session($user -> {"user_id"},
                                                   $self -> {"cgi"} -> param("persist"),
                                                   {"savestate" => $self -> get_saved_state()});

            $self -> log("login", $user -> {"username"});
            ($title, $body, $extrahead) = $self -> generate_loggedin();
        }

    # Has a registration attempt been made?
    } elsif(defined($self -> {"cgi"} -> param("register"))) {

        # Validate/perform the registration
        my ($user, $args) = $self -> validate_register();

        # Do we have any errors? If so, send back the login form with them
        if(!ref($user)) {
            $self -> log("registration error", $user);
            ($title, $body) = $self -> generate_login_form($user, $args);

        # No errors, user is registered
        } else {
            # Do not create a new session - the user needs to confirm the account.
            $self -> log("registered inactive", $user -> {"username"});
            ($title, $body) = $self -> generate_registered();
        }
    # Is the user attempting activation?
    } elsif(defined($self -> {"cgi"} -> param("actcode"))) {

        my ($user, $args) = $self -> validate_actcode();
        if(!ref($user)) {
            $self -> log("activation error", $user);
            ($title, $body) = $self -> generate_actcode_form($user);
        } else {
            $self -> log("activation success", $user -> {"username"});
            ($title, $body) = $self -> generate_activated($user);
        }

    } elsif(defined($self -> {"cgi"} -> param("activate"))) {
        ($title, $body) = $self -> generate_actcode_form();

    # No session, no submission? Send back the login form...
    } else {
        ($title, $body) = $self -> generate_login_form();
    }

    # Done generating the page content, return the filled in page template
    return $self -> {"template"} -> load_template("feature/login/page.tem", {"***title***"     => $title,
                                                                             "***extrahead***" => $extrahead,
                                                                             "***content***"   => $body,});
}

1;
