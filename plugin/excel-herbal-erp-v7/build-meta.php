<?php
if(!defined('ABSPATH'))exit;
// A deployed UAT pins its verified source in wp-config.php. Never overwrite it.
if(!defined('EH7_SOURCE_HEAD'))define('EH7_SOURCE_HEAD','local-integrated-v15-workflow-unverified');
