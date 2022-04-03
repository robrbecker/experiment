import 'dart:io';
import 'package:github/github.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

///////////////////////////////////////////////////////////
const mainBranchName = 'main';
const semver_major = 'semver:major';
const semver_minor = 'semver:minor';
const semver_patch = 'semver:patch';
const semvers = [semver_major, semver_minor, semver_patch];
const fullrepo = 'robrbecker/experiment';
///////////////////////////////////////////////////////////

var gh = GitHub(auth: findAuthenticationFromEnvironment());
var slug = RepositorySlug.full(fullrepo);

Future<void> main(List<String> args) async {
  // get the latest released version
  var latestVersion = await getLatestVersion(slug);

  // get all PRs (issues) that are merged but unreleased
  var unreleased = await getUnreleasedPRs();

  if (unreleased.isEmpty) {
    print('No unreleased PRs found');
    return;
  }

  // Calculate the next version
  var nextVersion = getNextVersion(latestVersion, unreleased);

  // Use the new version to generate release notes
  var notes = await generateReleaseNotes(latestVersion.toString(), nextVersion);

  // update the changelog with the new release notes
  updateChangeLog(notes);

  // update the version in the pubspec
  updatePubspec(nextVersion);

  // commit those changes and push them
  commitUpdates(nextVersion);

  // create a new release in github at main
  createRelease(nextVersion, mainBranchName);

  exit(0);
}

String run(String cmd, {List<String>? rest}) {
  var args = <String>[];
  if (rest != null) {
    args = rest;
  } else {
    args = cmd.split(' ');
    if (args.isEmpty) {
      return '';
    }
    cmd = args.removeAt(0);
  }
  var result = Process.runSync(cmd, args);
  if (result.exitCode != 0) {
    print('Command failed');
  }
  if (result.stdout != null) {
    print(result.stdout);
  }
  if (result.stderr != null) {
    print(result.stderr);
  }
  if (result.exitCode != 0) {
    exit(6);
  }

  return result.stdout;
}

Future<Version> getLatestVersion(RepositorySlug slug) async {
  var latestRelease = await gh.repositories.getLatestRelease(slug);
  var latestTag = latestRelease.tagName!;
  print('Latest Tag: $latestTag');
  return Version.parse(latestTag);
}

Future<List<Issue>> getUnreleasedPRs() async {
  print('Loading unreleased PRs...');
  var prs = await gh.search.issues('repo:${slug.fullName} is:pull-request label:unreleased state:closed', sort: 'desc').toList();
  print('${prs.length} loaded');
  return prs;
}

String getNextVersion(Version currentVersion, List<Issue> unreleased) {
  var semvers = Set<String>();
  for (var pr in unreleased){
    var prlabels = pr.labels.where((element) => element.name.startsWith('semver:')).toList();
    for (var l in prlabels) {
      semvers.add(l.name);
    }
  }
  print('Calculating next version based on $semvers');
  var newVersion = '';
  if (semvers.contains('semver:major')) {
    newVersion = currentVersion.nextMajor.toString();
  } else if (semvers.contains('semver:minor')) {
    newVersion = currentVersion.nextMinor.toString();
  } else if (semvers.contains('semver:patch')) {
    newVersion = currentVersion.nextPatch.toString();
  }
  print('Next Version: $newVersion');
  return newVersion;
}

Future<String> generateReleaseNotes(String fromVersion, String newVersion) async {
  var notes = await gh.repositories.generateReleaseNotes(CreateReleaseNotes(
      slug.owner, slug.name, newVersion,
      previousTagName: fromVersion));
  
  var releaseNotes = notes.body.replaceFirst('## What\'s Changed', '');
  
  var r = '## $newVersion\n$releaseNotes';
  print(r);
  return r;
}

void updateChangeLog(String notes) {
  var log = File('CHANGELOG.md');
  var logdata = log.existsSync() ? log.readAsStringSync() : '';
  log.writeAsStringSync('$notes\n\n$logdata');
}

void updatePubspec(String newVersion) {
  var f = File('pubspec.yaml');
  var editor = YamlEditor(f.readAsStringSync());
  editor.update(['version'], newVersion);
  f.writeAsStringSync(editor.toString());
}

Future<Release> createRelease(String version, String target) async {
    return gh.repositories.createRelease(
      slug,
      CreateRelease.from(
          tagName: version,
          name: version,
          generateReleaseNotes: true,
          targetCommitish: target,
          isDraft: false,
          isPrerelease: false));
}

void commitUpdates(String version) {
  run('git add pubspec.yaml CHANGELOG.md');
  run('git', rest: ['commit', '-m', 'prep $version']);
  run('git push');
}