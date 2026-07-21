'use strict';

document.addEventListener('submit', (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.classList.contains('delete-form')) {
    return;
  }

  // The name is read as DOM text from a safely HTML-encoded data attribute;
  // it is never interpolated into executable JavaScript source.
  const memberName = form.dataset.memberName || 'this member';
  if (!window.confirm(`Delete ${memberName}?`)) {
    event.preventDefault();
  }
});
