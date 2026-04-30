import { Server as IOServer } from 'socket.io'
import { Server as HTTPServer } from 'http'
import { getUser } from './auth'
import { supabase } from './supabase'

export interface WebSocketUser {
  id: string
  organizationId: string
  name: string
  email: string
}

export interface CommentData {
  id: string
  content: string
  author: {
    id: string
    name: string
    email: string
  }
  itemType: 'incident' | 'problem' | 'change'
  itemId: string
  mentions: string[]
  createdAt: string
  updatedAt: string
}

export interface RealtimeUpdate {
  type: 'comment_added' | 'comment_updated' | 'comment_deleted' | 'status_changed' | 'assignment_changed'
  data: any
  itemType: 'incident' | 'problem' | 'change'
  itemId: string
  organizationId: string
}

class WebSocketServer {
  private io: IOServer | null = null
  private userSessions: Map<string, WebSocketUser> = new Map()

  init(server: HTTPServer) {
    this.io = new IOServer(server, {
      cors: {
        origin: process.env.NODE_ENV === 'production' 
          ? process.env.NEXT_PUBLIC_APP_URL || 'https://your-domain.com'
          : ['http://localhost:3000', 'http://localhost:3001'],
        methods: ['GET', 'POST']
      }
    })

    this.io.on('connection', (socket) => {
      console.log('Client connected:', socket.id)

      // Authenticate user on connection
      socket.on('authenticate', async (token: string) => {
        try {
          // Validate token and get user info
          const user = await this.authenticateUser(token)
          if (user) {
            this.userSessions.set(socket.id, user)
            socket.join(`org:${user.organizationId}`)
            socket.emit('authenticated', { success: true, user })
            console.log(`User ${user.name} authenticated and joined org:${user.organizationId}`)
          } else {
            socket.emit('authenticated', { success: false, error: 'Invalid token' })
          }
        } catch (error) {
          console.error('Authentication error:', error)
          socket.emit('authenticated', { success: false, error: 'Authentication failed' })
        }
      })

      // Join specific item room for focused updates
      socket.on('join_item', (data: { itemType: string, itemId: string }) => {
        const user = this.userSessions.get(socket.id)
        if (user) {
          const roomName = `${data.itemType}:${data.itemId}`
          socket.join(roomName)
          console.log(`User ${user.name} joined room ${roomName}`)
        }
      })

      // Leave specific item room
      socket.on('leave_item', (data: { itemType: string, itemId: string }) => {
        const roomName = `${data.itemType}:${data.itemId}`
        socket.leave(roomName)
        console.log(`User left room ${roomName}`)
      })

      // Handle disconnect
      socket.on('disconnect', () => {
        const user = this.userSessions.get(socket.id)
        if (user) {
          console.log(`User ${user.name} disconnected`)
          this.userSessions.delete(socket.id)
        }
      })
    })

    return this.io
  }

  private async authenticateUser(token: string): Promise<WebSocketUser | null> {
    try {
      // Set the JWT token for supabase auth
      const { data: { user }, error } = await supabase.auth.getUser(token)
      
      if (error || !user) {
        return null
      }

      // Get user profile with organization info
      const { data: _profile, error: profileError } = await supabase
        .from('profiles')
        .select('full_name, email, organization_id')
        .eq('id', user.id)
        .single()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const profile: any = _profile

      if (profileError || !profile) {
        return null
      }

      return {
        id: user.id,
        organizationId: profile.organization_id as string,
        name: profile.full_name as string,
        email: profile.email as string
      }
    } catch (error) {
      console.error('User authentication error:', error)
      return null
    }
  }

  // Broadcast update to organization members
  broadcastToOrganization(organizationId: string, update: RealtimeUpdate) {
    if (this.io) {
      this.io.to(`org:${organizationId}`).emit('realtime_update', update)
      console.log(`Broadcasted ${update.type} to org:${organizationId}`)
    }
  }

  // Broadcast update to specific item watchers
  broadcastToItem(itemType: string, itemId: string, update: RealtimeUpdate) {
    if (this.io) {
      const roomName = `${itemType}:${itemId}`
      this.io.to(roomName).emit('realtime_update', update)
      console.log(`Broadcasted ${update.type} to room:${roomName}`)
    }
  }

  // Send notification to specific user
  sendNotificationToUser(userId: string, notification: any) {
    if (this.io) {
      // Find user's socket by user ID
      for (const [socketId, user] of this.userSessions.entries()) {
        if (user.id === userId) {
          this.io.to(socketId).emit('notification', notification)
          console.log(`Sent notification to user ${user.name}`)
        }
      }
    }
  }

  getConnectedUsers(organizationId: string): WebSocketUser[] {
    return Array.from(this.userSessions.values())
      .filter(user => user.organizationId === organizationId)
  }
}

export const wsServer = new WebSocketServer()
export default wsServer