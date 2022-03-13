import 'dart:io';
import 'package:github/github.dart';
import 'package:yaml/yaml.dart';

const semvers = ['major', 'minor', 'patch'];

/// Meant to be run from the github workflow.
/// Expected argument of PR_NUMBER of which to get
/// the semver label from
void main(List<String> args) async {
  if (args.length < 1) {
    print('Usage: release pullid');
    exit(0);
  }
  print(args);
  return;
  
  // install Cider and make sure were on a clean master
  //Process.runSync('pub', ['global', 'activate', 'cider']);
  // Process.runSync('git', ['checkout', 'master', '-f']);
  // Process.runSync('git', ['pull']);

  var currentVersion = getVersion();

  var slug = RepositorySlug('SpinlockLabs','github.dart');
  var number = int.parse(args[0]);
  print('Loading PR $number from $slug');
  var gh = GitHub(auth: findAuthenticationFromEnvironment());
  print('TOKEN: ${gh.auth?.token}');
  var pr = await gh.pullRequests.get(slug, number);
  if (!(pr.merged ?? false)) {
    print('PR not merged');
    exit(0);
  }
  print('PR loaded');

  var labels = pr.labels ?? [];
  var semverLabel = labels
      .map((e) => e.name)
      .firstWhere((label) => label.startsWith('semver'), orElse: () => '');
  if (semverLabel.isEmpty) {
    print('No semver label found');
    exit(0);
  }
  semverLabel = semverLabel.replaceAll('semver:', '');
  // ensure the semver label is valid
  if (!semvers.contains(semverLabel)) {
    print('semver label is not one of $semvers');
    exit(0);
  }
  print('Semver label: $semverLabel');
  Process.runSync('cider', ['bump', semverLabel]);
  var newVersion = getVersion();
  print('Current Version: $currentVersion');
  print('New Version    : $newVersion');

  var rn = await gh.repositories.generateReleaseNotes(CreateReleaseNotes(
      slug.owner, slug.name, newVersion,
      previousTagName: currentVersion));

  var releaseNotes = rn.body.replaceFirst('## What\'s Changed','');
  releaseNotes = '## $newVersion\n$releaseNotes';
  print(releaseNotes);
  var log = File('CHANGELOG.md');
  var logdata = log.readAsStringSync();
  
  log.writeAsStringSync('${releaseNotes}\n\n$logdata');
  
  // Process.runSync('git', ['add', 'pubspec.yaml', 'CHANGELOG.md']);
  // Process.runSync('git', ['commit', '-m', 'auto prep $newVersion']);
  // Process.runSync('git', ['push']);
  var res = Process.runSync('git', ['rev-parse', 'HEAD']);
  var commit = res.stdout;
  print('autoprep commit: $commit');

  // var release = await gh.repositories.createRelease(
  //     slug,
  //     CreateRelease.from(
  //         tagName: newVersion,
  //         name: newVersion,
  //         generateReleaseNotes: true,
  //         targetCommitish: commit,
  //         isDraft: false,
  //         isPrerelease: false));

  // print('$newVersion release created at ${release.createdAt}');
  
  exit(0);
}

String getVersion() {
  var y = loadYaml(File('pubspec.yaml').readAsStringSync());
  var newVersion = y['version'].toString();
  return newVersion;
}
