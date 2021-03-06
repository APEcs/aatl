-- phpMyAdmin SQL Dump
-- version 3.4.9
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Generation Time: Apr 16, 2012 at 10:32 PM
-- Server version: 5.1.56
-- PHP Version: 5.3.10-pl0-gentoo

SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `aatl`
--

-- --------------------------------------------------------

--
-- Table structure for table `auth_methods`
--

CREATE TABLE `auth_methods` (
  `id` tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  `perl_module` varchar(100) NOT NULL COMMENT 'The name of the AuthMethod (no .pm extension)',
  `priority` tinyint(4) NOT NULL COMMENT 'The authentication method''s priority. -128 = max, 127 = min',
  `enabled` tinyint(1) NOT NULL COMMENT 'Is this auth method usable?',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Stores the authentication methods supported by the system';

-- --------------------------------------------------------

--
-- Table structure for table `auth_methods_params`
--

CREATE TABLE `auth_methods_params` (
  `method_id` tinyint(4) NOT NULL COMMENT 'The id of the auth method',
  `name` varchar(40) NOT NULL COMMENT 'The parameter mame',
  `value` text NOT NULL COMMENT 'The value for the parameter',
  KEY `method_id` (`method_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Stores the settings for each auth method';

-- --------------------------------------------------------

--
-- Table structure for table `blocks`
--

CREATE TABLE `blocks` (
  `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT COMMENT 'Unique ID for this block entry',
  `name` varchar(32) NOT NULL,
  `module_id` smallint(5) unsigned NOT NULL COMMENT 'ID of the module implementing this block',
  `args` varchar(128) NOT NULL COMMENT 'Arguments passed verbatim to the block module',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='web-accessible page modules';

-- --------------------------------------------------------

--
-- Table structure for table `log`
--

CREATE TABLE `log` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `logtime` int(10) unsigned NOT NULL COMMENT 'The time the logged event happened at',
  `user_id` int(10) unsigned DEFAULT NULL COMMENT 'The id of the user who triggered the event, if any',
  `ipaddr` varchar(16) DEFAULT NULL COMMENT 'The IP address the event was triggered from',
  `logtype` varchar(64) NOT NULL COMMENT 'The event type',
  `logdata` varchar(255) DEFAULT NULL COMMENT 'Any data that might be appropriate to log for this event',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Stores a log of events in the system.';

-- --------------------------------------------------------

--
-- Table structure for table `modules`
--

CREATE TABLE `modules` (
  `module_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT COMMENT 'Unique module id',
  `name` varchar(80) NOT NULL COMMENT 'Short name for the module',
  `perl_module` varchar(128) NOT NULL COMMENT 'Name of the perl module in blocks/ (no .pm extension!)',
  `active` tinyint(1) unsigned NOT NULL COMMENT 'Is this module enabled?',
  PRIMARY KEY (`module_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Available site modules, perl module names, and status';

-- --------------------------------------------------------

--
-- Table structure for table `sessions`
--

CREATE TABLE `sessions` (
  `session_id` char(32) NOT NULL,
  `session_user_id` int(10) unsigned NOT NULL,
  `session_start` int(11) unsigned NOT NULL,
  `session_time` int(11) unsigned NOT NULL,
  `session_ip` varchar(40) NOT NULL,
  `session_autologin` tinyint(1) unsigned NOT NULL,
  PRIMARY KEY (`session_id`),
  KEY `session_time` (`session_time`),
  KEY `session_user_id` (`session_user_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Website sessions';

-- --------------------------------------------------------

--
-- Table structure for table `session_keys`
--

CREATE TABLE `session_keys` (
  `key_id` char(32) COLLATE utf8_bin NOT NULL DEFAULT '',
  `user_id` int(10) unsigned NOT NULL DEFAULT '0',
  `last_ip` varchar(40) COLLATE utf8_bin NOT NULL DEFAULT '',
  `last_login` int(11) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`key_id`,`user_id`),
  KEY `last_login` (`last_login`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='Autologin keys';

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE `settings` (
  `name` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `value` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci COMMENT='Site settings';

--
-- Dumping data for table `settings`
--

INSERT INTO `settings` (`name`, `value`) VALUES
('base', '/path/to/webapp/dir'),
('scriptpath', '/webpath'),
('cookie_name', 'cookiename'),
('cookie_path', '/'),
('cookie_domain', ''),
('cookie_secure', '1'),
('default_style', 'default'),
('logfile', ''),
('default_block', '1'),
('Auth:allow_autologin', '1'),
('Auth:max_autologin_time', '30'),
('Auth:ip_check', '4'),
('Auth:session_length', '3600'),
('Auth:session_gc', '7200'),
('Auth:unique_id', '2321'),
('Session:lastgc', '1334322698'),
('Core:envelope_address', 'some@valid.email'),
('Log:all_the_things', '1'),
('timefmt', '%d %b %Y %H:%M:%S %Z'),
('datefmt', '%d %b %Y');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `user_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_auth` tinyint(3) unsigned DEFAULT NULL COMMENT 'Id of the user''s auth method',
  `user_type` tinyint(3) unsigned DEFAULT '0' COMMENT 'The user type, 0 = normal, 3 = admin',
  `username` varchar(32) NOT NULL,
  `password` char(59) DEFAULT NULL,
  `created` int(10) unsigned NOT NULL COMMENT 'The unix time at which this user was created',
  `last_login` int(10) unsigned NOT NULL COMMENT 'The unix time of th euser''s last login',
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Stores the local user data for each user in the system';

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
