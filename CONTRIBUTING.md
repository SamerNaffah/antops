# Contributing to ANTOPS

Thank you for your interest in contributing to ANTOPS! We welcome contributions from the community.By contributing, you agree that your code will be licensed under MIT.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs **actual behavior**
- **Screenshots** if applicable
- **Environment details** (OS, Node version, browser, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear title and description**
- **Use case** - why this enhancement would be useful
- **Proposed solution** - how you envision it working
- **Alternatives considered**

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our coding standards
3. **Test your changes** thoroughly
4. **Update documentation** as needed
5. **Commit your changes** with clear messages
6. **Push to your fork** and submit a pull request

## Development Setup

### Prerequisites

- Node.js 20+
- npm or yarn
- Supabase account

### Setup Steps

```bash
# Clone your fork
git clone https://github.com/SamerNaffah/antops.git
cd antops/antops-app

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env.local
# Edit .env.local with your credentials

# Run development server
npm run dev
```

## Coding Standards

### TypeScript

- Use TypeScript for all new code
- Enable strict type checking
- Avoid `any` type when possible
- Document complex types

### Code Style

- Follow existing code formatting
- Use ESLint configuration
- Run `npm run lint` before committing
- Use meaningful variable and function names

### React Components

- Use functional components with hooks
- Keep components small and focused
- Extract reusable logic into custom hooks
- Use TypeScript interfaces for props

Example:

```typescript
interface ButtonProps {
  label: string;
  onClick: () => void;
  variant?: 'primary' | 'secondary';
}

export function Button({ label, onClick, variant = 'primary' }: ButtonProps) {
  return (
    <button onClick={onClick} className={`btn-${variant}`}>
      {label}
    </button>
  );
}
```

### File Organization

- Place components in `src/components/`
- Place utilities in `src/lib/`
- Place API routes in `src/app/api/`
- Place pages in `src/app/`

### Naming Conventions

- Components: PascalCase (e.g., `IncidentList.tsx`)
- Utilities: camelCase (e.g., `formatDate.ts`)
- Constants: UPPER_SNAKE_CASE (e.g., `MAX_FILE_SIZE`)
- CSS classes: kebab-case (e.g., `incident-card`)

## Commit Messages

Follow conventional commits format:

```
type(scope): subject

body

footer
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:

```
feat(incidents): add bulk assignment feature

Allow users to assign multiple incidents to a team member at once.
Includes UI updates and API endpoint.

Closes #123
```

```
fix(auth): resolve session timeout issue

Fix bug where users were logged out prematurely.
Update session expiry logic to match configuration.

Fixes #456
```

## Testing

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm test -- --watch

# Run specific test file
npm test -- IncidentList.test.tsx
```

### Writing Tests

- Write tests for new features
- Update tests when changing existing code
- Aim for good coverage of critical paths
- Use descriptive test names

Example:

```typescript
describe('IncidentList', () => {
  it('renders list of incidents', () => {
    // Test implementation
  });

  it('filters incidents by status', () => {
    // Test implementation
  });

  it('handles empty state', () => {
    // Test implementation
  });
});
```

## Documentation

- Update README.md for user-facing changes
- Add JSDoc comments for complex functions
- Update API documentation for API changes
- Include code examples when helpful

Example:

```typescript
/**
 * Formats a date according to user's locale
 * @param date - The date to format
 * @param format - The format string (default: 'MMM dd, yyyy')
 * @returns Formatted date string
 */
export function formatDate(date: Date, format = 'MMM dd, yyyy'): string {
  // Implementation
}
```

## Database Changes

If your contribution involves database changes:

1. Create a migration file in `database-migrations/`
2. Use descriptive naming: `YYYYMMDD_description.sql`
3. Include both UP and DOWN migrations if possible
4. Test migrations on a clean database
5. Document schema changes in PR description

Example migration:

```sql
-- Add priority column to incidents table
ALTER TABLE incidents
ADD COLUMN priority TEXT CHECK (priority IN ('low', 'medium', 'high', 'critical'))
DEFAULT 'medium';

-- Add index for better performance
CREATE INDEX idx_incidents_priority ON incidents(priority);
```

## Pull Request Process

1. **Create a descriptive PR title**
   - Use conventional commit format
   - Be specific about what changed

2. **Fill out the PR template**
   - Describe the changes
   - Link related issues
   - Note any breaking changes

3. **Request review**
   - Tag relevant reviewers
   - Respond to feedback promptly
   - Make requested changes

4. **Ensure CI passes**
   - All tests must pass
   - No linting errors
   - Build succeeds

5. **Squash commits** (optional)
   - Consider squashing for cleaner history
   - Keep meaningful commit messages

## Review Process

- Maintainers will review your PR
- Expect feedback and questions
- Be open to suggestions
- Once approved, a maintainer will merge

## Community

- Join our [Discord](https://discord.gg/antops) (if applicable)
- Follow us on [Twitter](https://twitter.com/antops) (if applicable)
- Read our [blog](https://antops.io/blog) (if applicable)

## Questions?

- Check existing [issues](https://github.com/SamerNaffah/antops/issues)
- Start a [discussion](https://github.com/SamerNaffah/antops/discussions)
- Email us at naffahsamer@gmail.com

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to ANTOPS! 🎉
