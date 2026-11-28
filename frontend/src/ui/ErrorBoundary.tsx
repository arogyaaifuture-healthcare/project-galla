import { Component, type ReactNode } from 'react'
// Never show a blank screen: any render error becomes a message with a retry button.
export class ErrorBoundary extends Component<{ children: ReactNode }, { err?: Error }> {
  state: { err?: Error } = {}
  static getDerivedStateFromError(err: Error) { return { err } }
  render() {
    if (!this.state.err) return this.props.children
    return (
      <div role="alert" className="panel center">
        <h2>Something went wrong</h2>
        <p>Your data is safe. Please try again.</p>
        <button className="btn" onClick={() => location.reload()}>Reload</button>
      </div>)
  }
}
