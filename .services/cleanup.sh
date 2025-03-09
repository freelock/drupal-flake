#!/usr/bin/env bash

    echo "Cleaning up Drupal installation..."
    rm -rf web vendor composer.* cms .init-complete settings.php launch-drupal-cms.sh recipes .editorconfig .gitattributes 2>/dev/null || true
    echo "Cleanup complete"
